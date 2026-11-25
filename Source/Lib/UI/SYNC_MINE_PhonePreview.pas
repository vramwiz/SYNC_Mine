unit SYNC_MINE_PhonePreview;

// 設定画面でスマホを描画し、ホイールとドラッグで表示範囲を操作する。

interface

uses
  System.Classes, System.Types, Vcl.Controls, SYNC_MINE_Conversation, SYNC_MINE_Renderer;

type
  TMinePhonePreview = class(TCustomControl)
  private
    FRenderer: TMineRenderer;
    FPhoneWidth, FPhoneHeight: Integer;
    FTimeMS: Integer;
    FPhoneColor: Cardinal;
    FZoom: Double;
    FPan: TPointF; // プレビューの中央からのずれをスマホ画像の座標で保持する。
    FDragging: Boolean;
    FLastMouse: TPoint;
    function FitScale: Double;
    procedure ClampPan;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Prepare(const Data: TMineConversation; Orientation: Integer);
    procedure ShowFrame(TimeMS: Integer; PhoneColor: Cardinal);
    // ポインターがプレビュー内にあるときだけホイールを処理する。
    function ZoomAt(const ClientPoint: TPoint; WheelDelta: Integer): Boolean;
  end;

implementation

uses
  System.Math, Winapi.GDIPOBJ, Winapi.Windows, Vcl.Graphics;

constructor TMinePhonePreview.Create(AOwner: TComponent);
begin
  inherited;
  FRenderer := TMineRenderer.Create;
  FZoom := 1;
  MinePhoneSize(0, FPhoneWidth, FPhoneHeight);
  ControlStyle := ControlStyle + [csOpaque];
  ParentDoubleBuffered := False;
  DoubleBuffered := True;
  Cursor := crSizeAll;
end;

destructor TMinePhonePreview.Destroy;
begin
  FRenderer.Free;
  inherited;
end;

procedure TMinePhonePreview.Prepare(const Data: TMineConversation; Orientation: Integer);
begin
  FRenderer.Prepare(Data, Orientation);
  MinePhoneSize(Orientation, FPhoneWidth, FPhoneHeight);
  ClampPan;
end;

procedure TMinePhonePreview.ShowFrame(TimeMS: Integer; PhoneColor: Cardinal);
begin
  FTimeMS := TimeMS;
  FPhoneColor := PhoneColor;
  Invalidate;
end;

function TMinePhonePreview.FitScale: Double;
var
  Margin: Integer;
begin
  Margin := ScaleValue(20);
  Result := Min(Max(1, ClientWidth - Margin) / FPhoneWidth,
    Max(1, ClientHeight - Margin) / FPhoneHeight);
end;

procedure TMinePhonePreview.ClampPan;
var
  Scale, MaxX, MaxY: Double;

  function PanLimit(ViewSize, PhoneSize: Integer): Double;
  var
    ViewSpan, MinVisible: Double;
  begin
    ViewSpan := ViewSize / Scale;
    // スマホの角丸の内側が画面に残るよう、画像座標でも最低幅を確保する。
    MinVisible := Min(Min(ViewSpan, PhoneSize), Max(48.0, ScaleValue(24) / Scale));
    Result := Max(0.0, (ViewSpan + PhoneSize) / 2 - MinVisible);
  end;

begin
  if (FPhoneWidth = 0) or ClientRect.IsEmpty then Exit;
  Scale := FitScale * FZoom;
  MaxX := PanLimit(ClientWidth, FPhoneWidth);
  MaxY := PanLimit(ClientHeight, FPhoneHeight);
  FPan.X := EnsureRange(FPan.X, -MaxX, MaxX);
  FPan.Y := EnsureRange(FPan.Y, -MaxY, MaxY);
end;

procedure TMinePhonePreview.Resize;
begin
  inherited;
  ClampPan;
  Invalidate;
end;

function TMinePhonePreview.ZoomAt(const ClientPoint: TPoint; WheelDelta: Integer): Boolean;
const
  MinZoom = 0.5;
  MaxZoom = 5.0;
  ZoomPerStep = 1.2;
var
  NewZoom, BaseScale, ShiftPerPixel: Double;
begin
  Result := ClientRect.Contains(ClientPoint) and (WheelDelta <> 0);
  if not Result then Exit;
  NewZoom := EnsureRange(FZoom * Power(ZoomPerStep, WheelDelta / WHEEL_DELTA), MinZoom, MaxZoom);
  if NewZoom = FZoom then Exit;
  BaseScale := FitScale;
  // ポインターが指すスマホ座標を、倍率変更の前後で同じ画面座標に置く。
  ShiftPerPixel := (1 / NewZoom - 1 / FZoom) / BaseScale;
  FPan.X := FPan.X + (ClientPoint.X - ClientWidth / 2) * ShiftPerPixel;
  FPan.Y := FPan.Y + (ClientPoint.Y - ClientHeight / 2) * ShiftPerPixel;
  FZoom := NewZoom;
  ClampPan;
  Invalidate;
end;

procedure TMinePhonePreview.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then Exit;
  FDragging := True;
  FLastMouse := Point(X, Y);
end;

procedure TMinePhonePreview.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Scale: Double;
begin
  inherited;
  if not FDragging then Exit;
  FDragging := MouseCapture and (ssLeft in Shift);
  if not FDragging then Exit;
  Scale := FitScale * FZoom;
  FPan.X := FPan.X + (X - FLastMouse.X) / Scale;
  FPan.Y := FPan.Y + (Y - FLastMouse.Y) / Scale;
  FLastMouse := Point(X, Y);
  ClampPan;
  Invalidate;
end;

procedure TMinePhonePreview.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then FDragging := False;
end;

procedure TMinePhonePreview.Paint;
var
  Target: TGPGraphics;
  Bounds: TRect;
  CenterX, CenterY, HalfWidth, HalfHeight, Scale: Double;
  X, Y, CellSize: Integer;
begin
  if ClientRect.IsEmpty then Exit;
  CellSize := Max(1, ScaleValue(16));
  for Y := 0 to (ClientHeight - 1) div CellSize do
    for X := 0 to (ClientWidth - 1) div CellSize do
    begin
      if Odd(X + Y) then Canvas.Brush.Color := $00353535
      else Canvas.Brush.Color := $003D3D3D;
      Canvas.FillRect(Rect(X * CellSize, Y * CellSize, (X + 1) * CellSize, (Y + 1) * CellSize));
    end;
  Scale := FitScale * FZoom;
  CenterX := ClientWidth / 2 + FPan.X * Scale;
  CenterY := ClientHeight / 2 + FPan.Y * Scale;
  HalfWidth := FPhoneWidth * Scale / 2;
  HalfHeight := FPhoneHeight * Scale / 2;
  Bounds := Rect(Round(CenterX - HalfWidth), Round(CenterY - HalfHeight),
    Round(CenterX + HalfWidth), Round(CenterY + HalfHeight));
  Target := TGPGraphics.Create(Canvas.Handle);
  try
    FRenderer.Draw(Target, Bounds, FTimeMS, FPhoneColor);
  finally
    Target.Free;
  end;
end;

end.
