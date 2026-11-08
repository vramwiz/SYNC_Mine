unit SYNC_MINE_ColorPicker;

// NicomeaのHSV部品を暗色ダイアログにまとめる。SV領域は常に正方形。

interface

uses
  System.Classes;

// RGBを編集し、閉じる操作で確定する。入力検証が通らない間は閉じない。
function EditMineColor(Owner: TComponent; const Title: string; var RGB: Cardinal): Boolean;

procedure CheckMineColorPicker(DPI: Integer; const Folder: string);

implementation

uses
  System.Math, System.SysUtils, System.IOUtils, Vcl.Imaging.pngimage, Winapi.Windows, Vcl.Controls, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, System.UITypes,
  ColorPickerColorMath, ColorPickerHueBar, ColorPickerSVArea,
  SYNC_MINE_DarkControls, SYNC_MusicStudio_DarkTheme;

type
  TMineColorPicker = class(TForm)
  private
    FArea: TColorPickerSVArea;
    FHueBar: TColorPickerHueBar;
    FSwatch: TPanel;
    FHex: TEdit;
    FAreaLabel, FHueLabel, FHexLabel, FHint: TLabel;
    FClose: TMineDarkButton;
    FSelected: Cardinal;
    FCurrentHue: Double;
    FReady, FUpdating, FCommitted: Boolean;
    function NewLabel(const Text: string): TLabel;
    function ReadHex(out RGB: Cardinal): Boolean;
    procedure Sync;
    procedure UpdateHue;
    procedure AreaChanged(Sender: TObject);
    procedure HueChanged(Sender: TObject);
    procedure HexChanged(Sender: TObject);
    procedure ClosePicker(Sender: TObject);
    procedure ConfirmClose(Sender: TObject; var CanClose: Boolean);
    procedure FitToWorkArea;
  protected
    procedure Resize; override;
    procedure DoShow; override;
    procedure DoAfterMonitorDpiChanged(OldDPI, NewDPI: Integer); override;
  public
    constructor CreateForColor(Owner: TComponent; const Title: string; RGB: Cardinal);
  end;

function RGBToVCL(RGB: Cardinal): TColor;
begin
  Result := Winapi.Windows.RGB((RGB shr 16) and $FF, (RGB shr 8) and $FF, RGB and $FF);
end;

function VCLToRGB(Color: TColor): Cardinal;
begin
  Color := ColorToRGB(Color);
  Result := (Cardinal(GetRValue(Color)) shl 16) or
    (Cardinal(GetGValue(Color)) shl 8) or GetBValue(Color);
end;

function TMineColorPicker.NewLabel(const Text: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := Text;
  Result.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
end;

constructor TMineColorPicker.CreateForColor(Owner: TComponent; const Title: string; RGB: Cardinal);
begin
  inherited CreateNew(Owner);
  Caption := Title;
  Position := poOwnerFormCenter;
  BorderIcons := [biSystemMenu];
  Font.PixelsPerInch := USER_DEFAULT_SCREEN_DPI;
  Font.IsDPIRelated := True;
  Font.Name := 'Yu Gothic UI';
  Font.Size := 10;
  ClientWidth := 430;
  ClientHeight := 350;
  DoubleBuffered := True;
  ApplySyncMusicStudioDarkForm(Self);
  FAreaLabel := NewLabel('彩度・明度');
  FHueLabel := NewLabel('色相');
  FHexLabel := NewLabel('色コード');
  FHint := NewLabel('閉じると選択した色を反映します。');
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
  FHex := TEdit.Create(Self);
  FHex.Parent := Self;
  FHex.MaxLength := 7;
  ApplySyncMusicStudioDarkEdit(FHex);
  FHex.OnChange := HexChanged;
  FClose := TMineDarkButton.Create(Self);
  FClose.Parent := Self;
  FClose.Caption := '閉じる';
  FClose.Cancel := True;
  FClose.OnClick := ClosePicker;
  OnCloseQuery := ConfirmClose;
  FSelected := RGB and $FFFFFF;
  UpdateHue;
  Sync;
  ScaleForPPI(CurrentPPI);
  ClientWidth := ScaleValue(430);
  ClientHeight := ScaleValue(350);
  FReady := True;
  Resize;
end;

procedure TMineColorPicker.Resize;
var
  Margin, Top, Size, HueLeft, EditLeft, EditWidth: Integer;
begin
  inherited;
  if not FReady then Exit;
  Margin := ScaleValue(14);
  Top := ScaleValue(38);
  // 幅・高さの両方から一辺だけを求め、DPIやウィンドウサイズでも縦横を揃える。
  Size := Max(1, Min(ScaleValue(256),
    Min(ClientHeight - Top - ScaleValue(56), ClientWidth - ScaleValue(160))));
  HueLeft := Margin + Size + ScaleValue(12);
  EditLeft := HueLeft + ScaleValue(34);
  EditWidth := Max(1, ClientWidth - EditLeft - Margin);
  FAreaLabel.SetBounds(Margin, Margin, Size, ScaleValue(22));
  FHueLabel.SetBounds(HueLeft, Margin, ScaleValue(34), ScaleValue(22));
  FArea.SetBounds(Margin, Top, Size, Size);
  FHueBar.SetBounds(HueLeft, Top, ScaleValue(22), Size);
  FSwatch.SetBounds(EditLeft, Top, EditWidth, ScaleValue(54));
  FHexLabel.SetBounds(EditLeft, Top + ScaleValue(70), EditWidth, ScaleValue(22));
  FHex.SetBounds(EditLeft, Top + ScaleValue(96), EditWidth, ScaleValue(28));
  FHint.SetBounds(Margin, ClientHeight - ScaleValue(38),
    Max(1, ClientWidth - ScaleValue(122)), ScaleValue(26));
  FHint.AutoSize := False;
  FHint.WordWrap := True;
  FClose.SetBounds(ClientWidth - Margin - ScaleValue(90),
    ClientHeight - Margin - ScaleValue(30), ScaleValue(90), ScaleValue(30));
end;

procedure TMineColorPicker.FitToWorkArea;
var
  Area: TRect;
  W, H: Integer;
begin
  Area := Monitor.WorkareaRect;
  Constraints.MinWidth := Min(ScaleValue(360), Area.Width);
  Constraints.MinHeight := Min(ScaleValue(290), Area.Height);
  W := Min(Width, Area.Width);
  H := Min(Height, Area.Height);
  SetBounds(EnsureRange(Left, Area.Left, Area.Right - W),
    EnsureRange(Top, Area.Top, Area.Bottom - H), W, H);
end;

procedure TMineColorPicker.DoShow;
begin
  FitToWorkArea;
  inherited;
end;

procedure TMineColorPicker.DoAfterMonitorDpiChanged(OldDPI, NewDPI: Integer);
begin
  inherited;
  FitToWorkArea;
  Resize;
end;

procedure TMineColorPicker.UpdateHue;
var
  Hue, Saturation, Value: Double;
begin
  ColorToHsv(RGBToVCL(FSelected), Hue, Saturation, Value);
  // 無彩色や黒への移動では、次のSV操作に使う色相を失わない。
  if (Saturation > 0.000001) and (Value > 0) then FCurrentHue := Hue;
end;

procedure TMineColorPicker.Sync;
begin
  FUpdating := True;
  try
    FHueBar.Color := HsvToColor(FCurrentHue, 1, 1);
    FArea.BaseColor := FHueBar.Color;
    FArea.Color := RGBToVCL(FSelected);
    FSwatch.Color := FArea.Color;
    FHex.Text := '#' + IntToHex(FSelected, 6);
    FHex.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  finally
    FUpdating := False;
  end;
end;

procedure TMineColorPicker.AreaChanged(Sender: TObject);
begin
  FSelected := VCLToRGB(FArea.Color);
  Sync;
end;

procedure TMineColorPicker.HueChanged(Sender: TObject);
var
  Saturation, Value: Double;
begin
  FCurrentHue := ColorHue(FHueBar.Color);
  ColorToSv(RGBToVCL(FSelected), Saturation, Value);
  FSelected := VCLToRGB(HsvToColor(FCurrentHue, Saturation, Value));
  Sync;
end;

function TMineColorPicker.ReadHex(out RGB: Cardinal): Boolean;
var
  Text: string;
  C: Char;
begin
  RGB := 0;
  Text := Trim(FHex.Text);
  if Text.StartsWith('#') then Delete(Text, 1, 1);
  if Length(Text) <> 6 then Exit(False);
  for C in Text do
    if not CharInSet(C, ['0'..'9', 'a'..'f', 'A'..'F']) then Exit(False);
  Result := TryStrToUInt('$' + Text, RGB);
end;

procedure TMineColorPicker.HexChanged(Sender: TObject);
var
  RGB: Cardinal;
begin
  if FUpdating then Exit;
  if not ReadHex(RGB) then
  begin
    FHex.Font.Color := $008080FF;
    Exit;
  end;
  FSelected := RGB;
  UpdateHue;
  // 入力位置は保ち、正規化はピッカー操作または閉じる際に行う。
  FUpdating := True;
  try
    FHueBar.Color := HsvToColor(FCurrentHue, 1, 1);
    FArea.BaseColor := FHueBar.Color;
    FArea.Color := RGBToVCL(FSelected);
    FSwatch.Color := FArea.Color;
    FHex.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  finally
    FUpdating := False;
  end;
end;

procedure TMineColorPicker.ClosePicker(Sender: TObject);
begin
  Close;
end;

procedure TMineColorPicker.ConfirmClose(Sender: TObject; var CanClose: Boolean);
var
  RGB: Cardinal;
begin
  CanClose := ReadHex(RGB);
  if not CanClose then
  begin
    MessageDlg('色コードは #RRGGBB の6桁で入力してください。', mtInformation, [mbOK], 0);
    FHex.SetFocus;
    Exit;
  end;
  FSelected := RGB;
  FCommitted := True;
end;

function EditMineColor(Owner: TComponent; const Title: string; var RGB: Cardinal): Boolean;
var
  Dialog: TMineColorPicker;
begin
  Dialog := TMineColorPicker.CreateForColor(Owner, Title, RGB);
  try
    Dialog.ShowModal;
    Result := Dialog.FCommitted;
    if Result then RGB := Dialog.FSelected;
  finally
    Dialog.Free;
  end;
end;

type
  TAreaAccess = class(TColorPickerSVArea);

procedure CheckMineColorPicker(DPI: Integer; const Folder: string);
var
  Dialog: TMineColorPicker;
  Bitmap: TBitmap;
  PNG: TPngImage;
  RGB: Cardinal;
  procedure Check(Value: Boolean; const Text: string);
  begin
    if not Value then raise Exception.CreateFmt('%d DPI picker: %s', [DPI, Text]);
  end;
begin
  Dialog := TMineColorPicker.CreateForColor(nil, 'アイコンの背景色', $FF0000);
  try
    Dialog.Show;
    Dialog.ScaleForPPI(DPI);
    Dialog.ClientWidth := Dialog.ScaleValue(430);
    Dialog.ClientHeight := Dialog.ScaleValue(350);
    Dialog.FitToWorkArea;
    Dialog.Resize;
    Check(Dialog.FArea.Width = Dialog.FArea.Height, 'SV square');
    Check(Dialog.FArea.BoundsRect.Bottom < Dialog.FClose.Top, 'square fits above footer');
    Check(Dialog.FHueBar.Height = Dialog.FArea.Height, 'hue same height');
    TAreaAccess(Dialog.FArea).MouseDown(mbLeft, [], 0, 0);
    Check(Dialog.FSelected = $FFFFFF, 'upper left white');
    TAreaAccess(Dialog.FArea).MouseDown(mbLeft, [], Dialog.FArea.Width - 1, 0);
    Check(Dialog.FSelected = $FF0000, 'upper right hue');
    TAreaAccess(Dialog.FArea).MouseDown(mbLeft, [], Dialog.FArea.Width - 1, Dialog.FArea.Height - 1);
    Check(Dialog.FSelected = 0, 'bottom black');
    Dialog.FHueBar.Color := clLime;
    Dialog.HueChanged(nil);
    Check(Dialog.FSelected = 0, 'hue preserves black');
    TAreaAccess(Dialog.FArea).MouseDown(mbLeft, [], Dialog.FArea.Width - 1, 0);
    Check(Dialog.FSelected = $00FF00, 'hue retained after black');
    Dialog.FHex.Text := '#123ABC';
    Check(Dialog.FSelected = $123ABC, 'hex live value');
    Dialog.FHex.Text := '#bad';
    Check(not Dialog.ReadHex(RGB), 'invalid hex rejected');
    Dialog.FHex.Text := '#336699';
    Dialog.Update;
    Bitmap := Dialog.GetFormImage;
    try
      PNG := TPngImage.Create;
      try
        PNG.Assign(Bitmap);
        PNG.SaveToFile(TPath.Combine(Folder, Format('picker-%d.png', [DPI])));
      finally PNG.Free; end;
    finally Bitmap.Free; end;
    Check(Dialog.CloseQuery and Dialog.FCommitted and (Dialog.FSelected = $336699), 'close saves color');
    Writeln(Format('PASS %d DPI picker: square=%dx%d, HSV, hex and close',
      [DPI, Dialog.FArea.Width, Dialog.FArea.Height]));
  finally Dialog.Free; end;
end;

end.