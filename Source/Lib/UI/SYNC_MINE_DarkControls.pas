unit SYNC_MINE_DarkControls;

// RhythmControlsのスライダー描画方式を使い、暗色のページ切り替えと揃える。

interface

uses
  System.Classes, Winapi.Messages, Vcl.ComCtrls, Vcl.Controls, Vcl.StdCtrls;

type
  // 入力可能なコンボの編集子ウィンドウにも、暗色背景と明色文字を適用する。
  TMineDarkEditableCombo = class(TComboBox)
  private
    FWindowText: string;
    FRestoreWindowText: Boolean;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TMineDarkButton = class(TButton)
  private
    FHover: Boolean;
    procedure CNDrawItem(var Message: TWMDrawItem); message CN_DRAWITEM;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure SetButtonStyle(ADefault: Boolean); override;
  end;

  TMineDarkTrackBar = class(TTrackBar)
  private
    procedure CNNotify(var Message: TWMNotify); message CN_NOTIFY;
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  // 選択ページを強調する3分割のナビゲーション。左右キーでも切り替えられる。
  TMinePageTabs = class(TCustomControl)
  private
    FActiveIndex, FHoverIndex: Integer;
    FOnChange: TNotifyEvent;
    procedure SetActiveIndex(Value: Integer);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    property ActiveIndex: Integer read FActiveIndex write SetActiveIndex;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses
  System.Math, System.Types, System.UITypes, Winapi.CommCtrl, Winapi.Windows,
  Winapi.UxTheme, Vcl.Graphics, SYNC_MusicStudio_DarkTheme;

const
  MINE_BORDER = TColor($00585858);
  MINE_ACCENT = TColor($009BCF9B);

constructor TMineDarkEditableCombo.Create(AOwner: TComponent);
begin
  inherited;
  Style := csDropDown;
  Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  StyleElements := StyleElements - [seClient, seFont];
end;

procedure TMineDarkEditableCombo.CreateWnd;
var
  Info: TComboBoxInfo;
  ChangeEvent: TNotifyEvent;
begin
  ChangeEvent := OnChange;
  OnChange := nil;
  try
    inherited;
    SetWindowTheme(Handle, 'DarkMode_CFD', nil);
    Info := Default(TComboBoxInfo);
    Info.cbSize := SizeOf(Info);
    if GetComboBoxInfo(Handle, Info) and (Info.hwndItem <> 0) then
    begin
      // 編集子ウィンドウのテーマ文字色を無効化し、CTLCOLOREDITの指定を使わせる。
      SetWindowTheme(Info.hwndItem, '', '');
      SendMessage(Info.hwndItem, WM_SETFONT, WPARAM(Font.Handle), 1);
    end;
    if FRestoreWindowText then
    begin
      Text := FWindowText;
      FRestoreWindowText := False;
      FWindowText := '';
    end;
  finally
    OnChange := ChangeEvent;
  end;
end;

procedure TMineDarkEditableCombo.DestroyWnd;
begin
  if HandleAllocated and not (csDestroying in ComponentState) then
  begin
    FWindowText := Text;
    FRestoreWindowText := True;
  end;
  inherited;
end;

procedure TMineDarkEditableCombo.WndProc(var Message: TMessage);
var
  DC: HDC;
begin
  if (Message.Msg = WM_CTLCOLOREDIT) or (Message.Msg = WM_CTLCOLORSTATIC) or
    (Message.Msg = CN_CTLCOLOREDIT) or (Message.Msg = CN_CTLCOLORSTATIC) then
  begin
    DC := HDC(Message.WParam);
    SetTextColor(DC, ColorToRGB(SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR));
    SetBkColor(DC, ColorToRGB(SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR));
    SetBkMode(DC, OPAQUE);
    Message.Result := LRESULT(Brush.Handle);
    Exit;
  end;
  inherited;
end;

procedure TMineDarkButton.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := (Params.Style and not $000F) or BS_OWNERDRAW;
end;

procedure TMineDarkButton.SetButtonStyle(ADefault: Boolean);
begin
  Invalidate;
end;

procedure TMineDarkButton.CMMouseEnter(var Message: TMessage);
begin
  inherited;
  FHover := True;
  Invalidate;
end;

procedure TMineDarkButton.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHover := False;
  Invalidate;
end;

procedure TMineDarkButton.CNDrawItem(var Message: TWMDrawItem);
var
  Surface: TCanvas;
  Bounds: TRect;
  Radius: Integer;
begin
  Message.Result := 1;
  if (Message.DrawItemStruct = nil) or (Message.DrawItemStruct.hDC = 0) then Exit;
  Surface := TCanvas.Create;
  try
    Surface.Handle := Message.DrawItemStruct.hDC;
    Bounds := Message.DrawItemStruct.rcItem;
    Surface.Brush.Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
    Surface.FillRect(Bounds);
    if FHover and Enabled then Surface.Brush.Color := $00454545
    else Surface.Brush.Color := $00333333;
    if Focused then Surface.Pen.Color := MINE_ACCENT else Surface.Pen.Color := MINE_BORDER;
    Radius := MulDiv(6, Font.PixelsPerInch, 96);
    InflateRect(Bounds, -1, -1);
    Surface.RoundRect(Bounds, Radius, Radius);
    Surface.Font.Assign(Font);
    if Enabled then Surface.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR
    else Surface.Font.Color := clGray;
    Surface.Brush.Style := bsClear;
    SelectObject(Surface.Handle, Surface.Font.Handle);
    SetTextColor(Surface.Handle, ColorToRGB(Surface.Font.Color));
    SetBkMode(Surface.Handle, TRANSPARENT);
    if Message.DrawItemStruct.itemState and ODS_SELECTED <> 0 then OffsetRect(Bounds, 1, 1);
    DrawText(Surface.Handle, PChar(Caption), -1, Bounds,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
  finally
    Surface.Handle := 0;
    Surface.Free;
  end;
end;

constructor TMineDarkTrackBar.Create(AOwner: TComponent);
begin
  inherited;
  StyleElements := [];
  TickStyle := tsNone;
  ShowSelRange := False;
  PositionToolTip := ptTop;
end;

procedure TMineDarkTrackBar.WMPaint(var Message: TWMPaint);
begin
  // 標準の青いバーが部分更新で残らないよう、毎回全体を描く。
  if Message.DC = 0 then InvalidateRect(Handle, nil, False);
  inherited;
end;

procedure TMineDarkTrackBar.CNNotify(var Message: TWMNotify);
var
  Draw: PNMCustomDraw;
  Surface: TCanvas;
  Channel, Thumb, Bounds: TRect;
  Y, H, PPI: Integer;
begin
  if Message.NMHdr.code <> NM_CUSTOMDRAW then
  begin
    inherited;
    Exit;
  end;
  Draw := PNMCustomDraw(Message.NMHdr);
  if Draw.dwDrawStage <> CDDS_PREPAINT then
  begin
    inherited;
    Exit;
  end;
  Message.Result := CDRF_SKIPDEFAULT;
  if Draw.hdc = 0 then Exit;
  Surface := TCanvas.Create;
  try
    Surface.Handle := Draw.hdc;
    Surface.Brush.Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
    Surface.FillRect(ClientRect);
    SendMessage(Handle, TBM_GETCHANNELRECT, 0, LPARAM(@Channel));
    SendMessage(Handle, TBM_GETTHUMBRECT, 0, LPARAM(@Thumb));
    PPI := Font.PixelsPerInch;
    Y := (Thumb.Top + Thumb.Bottom) div 2;
    H := System.Math.Max(2, MulDiv(3, PPI, 96));
    Bounds := Rect(Channel.Left, Y - H div 2, Channel.Right, Y + (H + 1) div 2);
    Surface.Brush.Color := MINE_BORDER;
    Surface.Pen.Color := MINE_BORDER;
    Surface.RoundRect(Bounds, H, H);
    Bounds.Right := (Thumb.Left + Thumb.Right) div 2;
    if Enabled then Surface.Brush.Color := MINE_ACCENT
    else Surface.Brush.Color := clGray;
    Surface.Pen.Color := Surface.Brush.Color;
    Surface.RoundRect(Bounds, H, H);
    Bounds := Rect(Bounds.Right - MulDiv(5, PPI, 96), Y - MulDiv(7, PPI, 96),
      Bounds.Right + MulDiv(5, PPI, 96), Y + MulDiv(7, PPI, 96));
    Surface.RoundRect(Bounds, H, H);
  finally
    Surface.Handle := 0;
    Surface.Free;
  end;
end;

constructor TMinePageTabs.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque];
  ParentBackground := False;
  ParentColor := False;
  Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
  TabStop := True;
  DoubleBuffered := True;
  FHoverIndex := -1;
end;

procedure TMinePageTabs.SetActiveIndex(Value: Integer);
begin
  Value := EnsureRange(Value, 0, 2);
  if Value = FActiveIndex then Exit;
  FActiveIndex := Value;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMinePageTabs.Paint;
const
  Captions: array[0..2] of string = ('メッセージ', 'アイコン', '設定');
var
  I, LineHeight: Integer;
  Bounds, TextBounds: TRect;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  LineHeight := Max(2, MulDiv(3, Font.PixelsPerInch, 96));
  for I := 0 to 2 do
  begin
    Bounds := Rect(MulDiv(Width, I, 3), 0, MulDiv(Width, I + 1, 3), Height);
    InflateRect(Bounds, -MulDiv(2, Font.PixelsPerInch, 96), 0);
    if I = FActiveIndex then Canvas.Brush.Color := $003B3B3B
    else if I = FHoverIndex then Canvas.Brush.Color := $00323232
    else Canvas.Brush.Color := Color;
    Canvas.FillRect(Bounds);
    if I = FActiveIndex then Canvas.Font.Color := MINE_ACCENT
    else Canvas.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
    TextBounds := Bounds;
    Dec(TextBounds.Bottom, LineHeight);
    Canvas.Brush.Style := bsClear;
    SelectObject(Canvas.Handle, Canvas.Font.Handle);
    SetTextColor(Canvas.Handle, ColorToRGB(Canvas.Font.Color));
    SetBkMode(Canvas.Handle, TRANSPARENT);
    DrawText(Canvas.Handle, PChar(Captions[I]), -1, TextBounds,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Brush.Style := bsSolid;
    if I = FActiveIndex then
    begin
      Canvas.Brush.Color := MINE_ACCENT;
      Bounds.Top := Bounds.Bottom - LineHeight;
      Canvas.FillRect(Bounds);
    end;
  end;
end;

procedure TMinePageTabs.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  inherited;
  Index := EnsureRange(X * 3 div Max(1, Width), 0, 2);
  if Index <> FHoverIndex then
  begin
    FHoverIndex := Index;
    Invalidate;
  end;
end;

procedure TMinePageTabs.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHoverIndex := -1;
  Invalidate;
end;

procedure TMinePageTabs.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS;
end;

procedure TMinePageTabs.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then Exit;
  if CanFocus then SetFocus;
  ActiveIndex := X * 3 div Max(1, Width);
end;

procedure TMinePageTabs.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  case Key of
    VK_LEFT: ActiveIndex := (FActiveIndex + 2) mod 3;
    VK_RIGHT: ActiveIndex := (FActiveIndex + 1) mod 3;
    VK_HOME: ActiveIndex := 0;
    VK_END: ActiveIndex := 2;
  else
    Exit;
  end;
  Key := 0;
end;

end.
