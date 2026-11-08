unit SYNC_MINE_PaletteEditor;

// 会話とスマホ本体の配色を、1列の対象選択と正方形HSVピッカーで直接編集する。

interface

uses
  System.Classes, Winapi.Messages, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls,
  ColorPickerHueBar, ColorPickerSVArea;

type
  TMineColorTarget = (mctBackground, mctText, mctOutgoing, mctIncoming, mctPhone);

  TMinePaletteEditor = class(TCustomControl)
  private
    FColors: array[TMineColorTarget] of Cardinal;
    FActiveTarget: TMineColorTarget;
    FCurrentHue: Double;
    FArea: TColorPickerSVArea;
    FHueBar: TColorPickerHueBar;
    FSwatch: TPanel;
    FColorCode: TLabel;
    FOnChange: TNotifyEvent;
    FReady: Boolean;
    procedure InitializeControls;
    function GetSelectedColor: Cardinal;
    procedure SetActiveTarget(Value: TMineColorTarget);
    procedure Sync;
    procedure AreaChanged(Sender: TObject);
    procedure HueChanged(Sender: TObject);
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    // フォームの会話を読み込む。ユーザー変更通知は発火しない。
    procedure SetPalette(Background, Text, Outgoing, Incoming, Phone: Cardinal);
    property ActiveTarget: TMineColorTarget read FActiveTarget write SetActiveTarget;
    property SelectedColor: Cardinal read GetSelectedColor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses
  System.Math, System.SysUtils, System.Types, Winapi.Windows, Vcl.Graphics,
  ColorPickerColorMath, SYNC_MusicStudio_DarkTheme;

const
  COLOR_TARGET_COUNT = Ord(High(TMineColorTarget)) + 1;
  TargetCaptions: array[TMineColorTarget] of string =
    ('背景', '文字色', '自分', '相手', 'スマホ');

function VCLColor(RGB: Cardinal): TColor;
begin
  Result := Winapi.Windows.RGB((RGB shr 16) and $FF, (RGB shr 8) and $FF, RGB and $FF);
end;

constructor TMinePaletteEditor.Create(AOwner: TComponent);
begin
  inherited;
  Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
  DoubleBuffered := True;
  TabStop := True;
  Width := 440;
  Height := 320;
end;

procedure TMinePaletteEditor.SetParent(AParent: TWinControl);
begin
  inherited;
  if AParent = nil then Exit;
  if not FReady then InitializeControls;
  Resize;
end;

procedure TMinePaletteEditor.InitializeControls;
begin
  // 子部品の親設定や文字計測でHandleを要求されるため、親の接続後に生成する。
  FArea := TColorPickerSVArea.Create(Self);
  FArea.Parent := Self;
  FArea.OnChange := AreaChanged;
  FHueBar := TColorPickerHueBar.Create(Self);
  FHueBar.Parent := Self;
  FHueBar.OnChange := HueChanged;
  FSwatch := TPanel.Create(Self);
  FSwatch.Parent := Self;
  FSwatch.ParentBackground := False;
  FSwatch.BevelOuter := bvNone;
  FColorCode := TLabel.Create(Self);
  FColorCode.AutoSize := False;
  FColorCode.Parent := Self;
  FColorCode.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  FColorCode.ParentFont := True;
  FReady := True;
  Sync;
end;

procedure TMinePaletteEditor.SetPalette(Background, Text, Outgoing, Incoming, Phone: Cardinal);
begin
  FColors[mctBackground] := Background and $FFFFFF;
  FColors[mctText] := Text and $FFFFFF;
  FColors[mctOutgoing] := Outgoing and $FFFFFF;
  FColors[mctIncoming] := Incoming and $FFFFFF;
  FColors[mctPhone] := Phone and $FFFFFF;
  Sync;
end;

function TMinePaletteEditor.GetSelectedColor: Cardinal;
begin
  Result := FColors[FActiveTarget];
end;

procedure TMinePaletteEditor.SetActiveTarget(Value: TMineColorTarget);
begin
  if Value = FActiveTarget then Exit;
  FActiveTarget := Value;
  Sync;
end;

procedure TMinePaletteEditor.Sync;
var
  Hue, Saturation, Value: Double;
begin
  if not FReady or (Parent = nil) then Exit;
  ColorToHsv(VCLColor(SelectedColor), Hue, Saturation, Value);
  if (Saturation > 0.000001) and (Value > 0) then FCurrentHue := Hue;
  FHueBar.Color := HsvToColor(FCurrentHue, 1, 1);
  FArea.BaseColor := FHueBar.Color;
  FArea.Color := VCLColor(SelectedColor);
  FSwatch.Color := FArea.Color;
  FColorCode.Caption := '#' + IntToHex(SelectedColor, 6);
  Invalidate;
end;

procedure TMinePaletteEditor.AreaChanged(Sender: TObject);
var
  C: TColor;
begin
  C := ColorToRGB(FArea.Color);
  FColors[FActiveTarget] := (Cardinal(GetRValue(C)) shl 16) or
    (Cardinal(GetGValue(C)) shl 8) or GetBValue(C);
  Sync;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMinePaletteEditor.HueChanged(Sender: TObject);
var
  Saturation, Value: Double;
begin
  FCurrentHue := ColorHue(FHueBar.Color);
  ColorToSv(FArea.Color, Saturation, Value);
  FArea.BaseColor := FHueBar.Color;
  FArea.Color := HsvToColor(FCurrentHue, Saturation, Value);
  AreaChanged(Sender);
end;

procedure TMinePaletteEditor.Resize;
var
  Top, Size, RightLeft: Integer;
begin
  inherited;
  if not FReady or (Parent = nil) then Exit;
  Top := ScaleValue(44);
  Size := Max(1, Min(ScaleValue(220), Min(ClientHeight - Top, ClientWidth - ScaleValue(90))));
  FArea.SetBounds(0, Top, Size, Size);
  FHueBar.SetBounds(Size + ScaleValue(8), Top, ScaleValue(18), Size);
  RightLeft := Size + ScaleValue(38);
  FSwatch.SetBounds(RightLeft, Top,
    Max(1, Min(ScaleValue(128), ClientWidth - RightLeft)), ScaleValue(30));
  FColorCode.SetBounds(RightLeft, Top + ScaleValue(38),
    Max(1, ClientWidth - RightLeft), ScaleValue(22));
  Invalidate;
end;

procedure TMinePaletteEditor.Paint;
var
  Target: TMineColorTarget;
  Bounds, TextBounds: TRect;
  RowHeight, LineHeight: Integer;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  RowHeight := ScaleValue(32);
  LineHeight := Max(2, ScaleValue(2));
  for Target := Low(TMineColorTarget) to High(TMineColorTarget) do
  begin
    Bounds := Rect(MulDiv(ClientWidth, Ord(Target), COLOR_TARGET_COUNT), 0,
      MulDiv(ClientWidth, Ord(Target) + 1, COLOR_TARGET_COUNT), RowHeight);
    InflateRect(Bounds, -ScaleValue(2), -ScaleValue(2));
    if Target = FActiveTarget then
    begin
      Canvas.Brush.Color := $003B3B3B;
      Canvas.Font.Color := $009BCF9B;
    end
    else
    begin
      Canvas.Brush.Color := $00303030;
      Canvas.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
    end;
    Canvas.FillRect(Bounds);
    TextBounds := Bounds;
    Dec(TextBounds.Bottom, LineHeight);
    Canvas.Brush.Style := bsClear;
    SelectObject(Canvas.Handle, Canvas.Font.Handle);
    SetTextColor(Canvas.Handle, ColorToRGB(Canvas.Font.Color));
    SetBkMode(Canvas.Handle, TRANSPARENT);
    DrawText(Canvas.Handle, PChar(TargetCaptions[Target]), -1, TextBounds,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Brush.Style := bsSolid;
    if Target = FActiveTarget then
    begin
      Canvas.Brush.Color := $009BCF9B;
      Bounds.Top := Bounds.Bottom - LineHeight;
      Canvas.FillRect(Bounds);
    end;
  end;
end;

procedure TMinePaletteEditor.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  inherited;
  if (Button <> mbLeft) or (Y < 0) or (Y >= ScaleValue(32)) then Exit;
  if CanFocus then SetFocus;
  Index := EnsureRange(X * COLOR_TARGET_COUNT div Max(1, ClientWidth), 0, COLOR_TARGET_COUNT - 1);
  ActiveTarget := TMineColorTarget(Index);
end;

procedure TMinePaletteEditor.KeyDown(var Key: Word; Shift: TShiftState);
var
  Index: Integer;
begin
  inherited;
  Index := Ord(FActiveTarget);
  case Key of
    VK_LEFT, VK_UP: Index := (Index + COLOR_TARGET_COUNT - 1) mod COLOR_TARGET_COUNT;
    VK_RIGHT, VK_DOWN: Index := (Index + 1) mod COLOR_TARGET_COUNT;
    VK_HOME: Index := 0;
    VK_END: Index := COLOR_TARGET_COUNT - 1;
  else
    Exit;
  end;
  ActiveTarget := TMineColorTarget(Index);
  Key := 0;
end;

procedure TMinePaletteEditor.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS;
end;

end.
