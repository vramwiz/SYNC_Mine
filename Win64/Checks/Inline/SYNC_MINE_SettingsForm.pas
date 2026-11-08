unit SYNC_MINE_SettingsForm;

// 会話・アイコン・基本設定を暗色の3ページで編集し、閉じる操作で確定する。

interface

function EditMineSettings(var JSON: string; var Orientation: Integer; var PhoneColor: Cardinal): Boolean;

procedure CheckMineInline(DPI: Integer; Compact: Boolean; const Folder: string);

implementation

uses
  System.Classes, System.IOUtils, Vcl.Imaging.pngimage, System.Math, System.SysUtils, System.Types, System.UITypes,
  Winapi.GDIPAPI, Winapi.GDIPOBJ, Winapi.Windows, Winapi.UxTheme, Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  SYNC_MusicStudio_DarkTheme, SYNC_MINE_Conversation, SYNC_MINE_CharacterIcons,
  SYNC_MINE_Renderer, SYNC_MINE_UserSettings, SYNC_MINE_DarkControls, SYNC_MINE_ColorPicker,
  ColorPickerColorMath, ColorPickerHueBar, ColorPickerSVArea;

type
  TAreaAccess = class(TColorPickerSVArea);
  TFormMineSettings = class(TForm)
  private
    FData: TMineConversation;
    FHistory: TMineCharacterHistory;
    FBuiltinNames: TStringList;
    FRenderer: TMineRenderer;
    FPhoneColor: Cardinal;
    FLoading, FDirty, FNameNeedsApply: Boolean;
    FLayoutReady, FUpdatingLayout: Boolean;
    FPreviewPanel, FPreviewFooter, FPageHost, FIconDetails, FFooter: TPanel;
    FPages: array[0..2] of TPanel;
    FNavigation: TMinePageTabs;
    FMessageScroll: TScrollBox;
    FCloseButton, FAddSpeakerButton, FDeleteSpeakerButton, FIconBrowse, FIconClear, FColorButton: TButton;
    FColorSwatch, FIconColorSwatch: TPanel;
    FIconHueBar: TColorPickerHueBar;
    FIconColorArea: TColorPickerSVArea;
    FIconCurrentHue: Double;
    FClosedCommitted: Boolean;
    FResultJSON: string;
    FMessageList, FSpeakerList: TListBox;
    FTitle, FTime, FPhoto, FIconFile: TEdit;
    FText: TMemo;
    FSender, FSide, FName, FOrientation: TComboBox;
    FScale, FIconX, FIconY, FStage: TTrackBar;
    FPreview, FIconPreview: TPaintBox;
    FStageLabel, FStatus, FMessageHint, FNameLabel, FSideLabel, FIconFileLabel,
      FScaleLabel, FIconXLabel, FIconYLabel, FIconFrameLabel, FIconColorLabel, FSettingsHint: TLabel;
    FTimer: TTimer;
    FIconImage: TGPBitmap;
    FIconImageFile: string;
    function LabelAt(Parent: TWinControl; const Caption: string; X, Y: Integer): TLabel;
    function ButtonAt(Parent: TWinControl; const Caption: string; X, Y, W: Integer;
      Click: TNotifyEvent): TButton;
    function EditAt(Parent: TWinControl; X, Y, W: Integer): TEdit;
    function ComboAt(Parent: TWinControl; X, Y, W: Integer): TComboBox;
    function SliderAt(Parent: TWinControl; X, Y, W, Low, High, Value: Integer): TTrackBar;
    procedure DrawCombo(Control: TWinControl; Index: Integer; Bounds: TRect; State: TOwnerDrawState);
    procedure DrawMessage(Control: TWinControl; Index: Integer; Bounds: TRect; State: TOwnerDrawState);
    function SpeakerCaption(Index: Integer): string;
    procedure UpdateMessageHint;
    procedure BuildMessagePage(Parent: TWinControl);
    procedure BuildIconPage(Parent: TWinControl);
    procedure BuildSettingsPage(Parent: TWinControl);
    procedure LayoutIconPage;
    procedure NavigationChanged(Sender: TObject);
    procedure SettingsChanged(Sender: TObject);
    procedure ChoosePhoneColor(Sender: TObject);
    procedure IconColorChanged(Sender: TObject);
    procedure IconHueChanged(Sender: TObject);
    procedure UpdatePhoneColor;
    procedure RefreshLists(MessageIndex, SpeakerIndex: Integer);
    function MessageCaption(Index: Integer): string;
    procedure LoadMessage(Sender: TObject);
    procedure LoadSpeaker(Sender: TObject);
    procedure MessageChanged(Sender: TObject);
    procedure SpeakerChanged(Sender: TObject);
    procedure AddMessage(Sender: TObject);
    procedure DeleteMessage(Sender: TObject);
    procedure MoveMessage(Sender: TObject);
    procedure AddSpeaker(Sender: TObject);
    procedure DeleteSpeaker(Sender: TObject);
    procedure ChoosePhoto(Sender: TObject);
    procedure ClearPhoto(Sender: TObject);
    procedure ChooseIcon(Sender: TObject);
    procedure ClearIcon(Sender: TObject);
    procedure UseCharacter(Sender: TObject);
    procedure CharacterNameExit(Sender: TObject);
    procedure CharacterNamesDropDown(Sender: TObject);
    procedure RememberCharacter;
    procedure RefreshCharacterNames;
    function ChooseImage(out FileName: string): Boolean;
    procedure RefreshIcon;
    procedure PaintIcon(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure PreviewChanged(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure CloseSettings(Sender: TObject);
    procedure ConfirmClose(Sender: TObject; var CanClose: Boolean);
    procedure FitToWorkArea;
  protected
    procedure DoShow; override;
    procedure DoAfterMonitorDpiChanged(OldDPI, NewDPI: Integer); override;
    procedure Resize; override;
  public
    constructor CreateForConversation(const JSON: string; Orientation: Integer; PhoneColor: Cardinal);
    destructor Destroy; override;
  end;

function TFormMineSettings.LabelAt(Parent: TWinControl; const Caption: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Parent;
  Result.Caption := Caption;
  Result.Left := X;
  Result.Top := Y;
  Result.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
end;

function TFormMineSettings.ButtonAt(Parent: TWinControl; const Caption: string;
  X, Y, W: Integer; Click: TNotifyEvent): TButton;
begin
  Result := TMineDarkButton.Create(Self);
  Result.Parent := Parent;
  Result.SetBounds(X, Y, W, 30);
  Result.Caption := Caption;
  Result.OnClick := Click;
  ApplySyncMusicStudioDarkButton(Result);
end;

function TFormMineSettings.EditAt(Parent: TWinControl; X, Y, W: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Parent;
  Result.SetBounds(X, Y, W, 28);
  ApplySyncMusicStudioDarkEdit(Result);
end;

function TFormMineSettings.ComboAt(Parent: TWinControl; X, Y, W: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := Parent;
  Result.SetBounds(X, Y, W, 28);
  Result.Style := csDropDownList;
  ApplySyncMusicStudioDarkComboBox(Result, DrawCombo);
end;

function TFormMineSettings.SliderAt(Parent: TWinControl; X, Y, W, Low, High, Value: Integer): TTrackBar;
begin
  Result := TMineDarkTrackBar.Create(Self);
  Result.Parent := Parent;
  Result.SetBounds(X, Y, W, 32);
  Result.Min := Low;
  Result.Max := High;
  Result.Position := Value;
  Result.TickStyle := tsNone;
  Result.PageSize := 10;
end;

procedure TFormMineSettings.DrawCombo(Control: TWinControl; Index: Integer; Bounds: TRect;
  State: TOwnerDrawState);
begin
  DrawSyncMusicStudioDarkComboBoxItem(TComboBox(Control), Index, Bounds, State, PixelsPerInch);
end;

function TFormMineSettings.SpeakerCaption(Index: Integer): string;
begin
  if FData.Speakers[Index].Outgoing then Result := '自分｜' else Result := '相手｜';
  Result := Result + FData.Speakers[Index].Name;
end;

procedure TFormMineSettings.DrawMessage(Control: TWinControl; Index: Integer;
  Bounds: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  TextBounds: TRect;
begin
  Canvas := TListBox(Control).Canvas;
  if odSelected in State then Canvas.Brush.Color := $0050473B
  else Canvas.Brush.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  Canvas.FillRect(Bounds);
  if (Index < 0) or (Index >= Length(FData.Messages)) then Exit;
  Canvas.Font.Assign(Font);
  if FData.Speakers[FData.Messages[Index].Speaker].Outgoing then Canvas.Font.Color := $00A1E8AC
  else Canvas.Font.Color := $00E8DFD6;
  TextBounds := Bounds;
  InflateRect(TextBounds, -ScaleValue(6), 0);
  SelectObject(Canvas.Handle, Canvas.Font.Handle);
  SetTextColor(Canvas.Handle, ColorToRGB(Canvas.Font.Color));
  SetBkMode(Canvas.Handle, TRANSPARENT);
  DrawText(Canvas.Handle, PChar(MessageCaption(Index)), -1, TextBounds,
    DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
end;

procedure TFormMineSettings.UpdateMessageHint;
var
  I, Start: Integer;
begin
  I := FMessageList.ItemIndex;
  if I < 0 then
  begin
    FMessageHint.Caption := '段階0は会話なし。「追加」からメッセージを作成してください。';
    Exit;
  end;
  Start := I * 100;
  if FData.Speakers[FData.Messages[I].Speaker].Outgoing then
    FMessageHint.Caption := Format('自分：%d〜%dで入力、%d〜%dで送信、%dで既読。',
      [Start, Start + 85, Start + 86, Start + 99, Start + 100])
  else FMessageHint.Caption := Format('相手：%d〜%dで吹き出し・写真が出現、%dで既読。',
      [Start, Start + 99, Start + 100]);
end;

constructor TFormMineSettings.CreateForConversation(const JSON: string; Orientation: Integer;
  PhoneColor: Cardinal);
var
  EditorPanel: TPanel;
  I: Integer;
  Hint: TLabel;
begin
  inherited CreateNew(nil);
  FData := TMineConversation.FromJSON(JSON);
  FHistory := TMineCharacterHistory.Create(TPath.Combine(ExtractFilePath(ParamStr(0)), 'History'));
  FHistory.Load;
  FBuiltinNames := TStringList.Create;
  MineCharacterNames(FBuiltinNames);
  FRenderer := TMineRenderer.Create;
  FPhoneColor := PhoneColor;
  FLoading := True;
  Caption := 'MINE の設定';
  Position := poScreenCenter;
  ClientWidth := 1040;
  ClientHeight := 740;
  // 配置とフォントを96 DPIで揃え、完成後にまとめて拡大する。
  Font.PixelsPerInch := USER_DEFAULT_SCREEN_DPI;
  Font.IsDPIRelated := True;
  Font.Name := 'Yu Gothic UI';
  Font.Size := 10;
  DoubleBuffered := True;
  OnCloseQuery := ConfirmClose;
  ApplySyncMusicStudioDarkForm(Self);

  FFooter := TPanel.Create(Self);
  FFooter.Parent := Self;
  FFooter.Align := alBottom;
  FFooter.Height := 40;
  FFooter.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(FFooter);
  Hint := LabelAt(FFooter, '閉じると変更を保存します。', 12, 12);
  Hint.Font.Color := $00B5B5B5;
  FCloseButton := ButtonAt(FFooter, '閉じる', ClientWidth - 110, 5, 98, CloseSettings);
  FCloseButton.Anchors := [akTop, akRight];
  FCloseButton.Cancel := True;

  FPreviewPanel := TPanel.Create(Self);
  FPreviewPanel.Parent := Self;
  FPreviewPanel.Align := alRight;
  FPreviewPanel.Width := 360;
  FPreviewPanel.BevelOuter := bvNone;
  FPreviewPanel.Padding.SetBounds(12, 12, 12, 12);
  ApplySyncMusicStudioDarkPanel(FPreviewPanel);
  FPreviewFooter := TPanel.Create(Self);
  FPreviewFooter.Parent := FPreviewPanel;
  FPreviewFooter.Align := alBottom;
  FPreviewFooter.Height := 92;
  FPreviewFooter.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(FPreviewFooter);
  FStageLabel := LabelAt(FPreviewFooter, '段階 0', 0, 4);
  FStage := SliderAt(FPreviewFooter, 0, 28, 336, 0, Max(100, Length(FData.Messages) * 100), 0);
  FStage.Frequency := 100;
  FStage.PageSize := 100;
  FStage.OnChange := PreviewChanged;
  FStatus := LabelAt(FPreviewFooter, '', 0, 66);
  FStatus.AutoSize := False;
  FStatus.SetBounds(0, 66, 336, 24);
  FPreview := TPaintBox.Create(Self);
  FPreview.Parent := FPreviewPanel;
  FPreview.Align := alClient;
  FPreview.OnPaint := PaintPreview;

  EditorPanel := TPanel.Create(Self);
  EditorPanel.Parent := Self;
  EditorPanel.Align := alClient;
  EditorPanel.BevelOuter := bvNone;
  EditorPanel.Padding.SetBounds(12, 12, 0, 12);
  ApplySyncMusicStudioDarkPanel(EditorPanel);
  FNavigation := TMinePageTabs.Create(Self);
  FNavigation.Parent := EditorPanel;
  FNavigation.Align := alTop;
  FNavigation.Height := 42;
  FNavigation.OnChange := NavigationChanged;
  FPageHost := TPanel.Create(Self);
  FPageHost.Parent := EditorPanel;
  FPageHost.Align := alClient;
  FPageHost.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(FPageHost);
  for I := 0 to 2 do
  begin
    FPages[I] := TPanel.Create(Self);
    FPages[I].Parent := FPageHost;
    FPages[I].Align := alClient;
    FPages[I].BevelOuter := bvNone;
    ApplySyncMusicStudioDarkPanel(FPages[I]);
  end;
  FMessageScroll := TScrollBox.Create(Self);
  FMessageScroll.Parent := FPages[0];
  FMessageScroll.Align := alClient;
  FMessageScroll.BorderStyle := bsNone;
  FMessageScroll.Color := SYNC_MUSIC_STUDIO_DARK_PANEL_COLOR;
  BuildMessagePage(FMessageScroll);
  BuildIconPage(FPages[1]);
  BuildSettingsPage(FPages[2]);
  FOrientation.ItemIndex := EnsureRange(Orientation, 0, 1);
  UpdatePhoneColor;
  FLoading := False;
  RefreshLists(0, 0);
  NavigationChanged(nil);
  FDirty := True;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 120;
  FTimer.OnTimer := Tick;
  DisableAlign;
  try
    ScaleForPPI(CurrentPPI);
    ClientWidth := ScaleValue(1040);
    ClientHeight := ScaleValue(740);
  finally
    EnableAlign;
  end;
  FLayoutReady := True;
  Resize;
end;

procedure TFormMineSettings.FitToWorkArea;
var
  Area: TRect;
  FitWidth, FitHeight: Integer;
begin
  Area := Monitor.WorkareaRect;
  Constraints.MinWidth := Min(ScaleValue(880), Area.Width);
  Constraints.MinHeight := Min(ScaleValue(500), Area.Height);
  if WindowState <> wsNormal then Exit;
  FitWidth := Min(Width, Area.Width);
  FitHeight := Min(Height, Area.Height);
  SetBounds(EnsureRange(Left, Area.Left, Area.Right - FitWidth),
    EnsureRange(Top, Area.Top, Area.Bottom - FitHeight), FitWidth, FitHeight);
end;

procedure TFormMineSettings.DoShow;
begin
  FitToWorkArea;
  inherited;
end;

procedure TFormMineSettings.DoAfterMonitorDpiChanged(OldDPI, NewDPI: Integer);
begin
  inherited;
  FitToWorkArea;
  Resize;
end;

procedure TFormMineSettings.Resize;
var
  W: Integer;
begin
  inherited;
  if not FLayoutReady or FUpdatingLayout or (csDestroying in ComponentState) then Exit;
  FUpdatingLayout := True;
  try
    FPreviewPanel.Width := Min(ScaleValue(360), Max(ScaleValue(180),
      ClientWidth - ScaleValue(660)));
    FStage.Width := FPreviewFooter.ClientWidth;
    FStatus.Width := FPreviewFooter.ClientWidth;
    FMessageScroll.HorzScrollBar.Margin := ScaleValue(12);
    FMessageScroll.VertScrollBar.Margin := ScaleValue(12);
    LayoutIconPage;
    W := Max(ScaleValue(100), FPages[2].ClientWidth - ScaleValue(24));
    FTitle.Width := W;
    FSettingsHint.Width := W;
    FSettingsHint.Visible := FPages[2].ClientHeight >= ScaleValue(300);
    FPreview.Invalidate;
    FIconPreview.Invalidate;
  finally
    FUpdatingLayout := False;
  end;
end;

procedure TFormMineSettings.LayoutIconPage;
var
  Margin, LeftWidth, W, H, Top, Row, ImageSize, SliderLeft, SliderHeight, PickerTop: Integer;
  Compact: Boolean;
begin
  Margin := ScaleValue(12);
  W := FPages[1].ClientWidth;
  H := FPages[1].ClientHeight;
  LeftWidth := Min(ScaleValue(132), Max(ScaleValue(96), W div 4));
  FSpeakerList.SetBounds(Margin, Margin, LeftWidth, Max(ScaleValue(60), H - Margin * 2 - ScaleValue(38)));
  FAddSpeakerButton.SetBounds(Margin, H - Margin - ScaleValue(30),
    (LeftWidth - ScaleValue(8)) div 2, ScaleValue(30));
  FDeleteSpeakerButton.SetBounds(FAddSpeakerButton.BoundsRect.Right + ScaleValue(8),
    FAddSpeakerButton.Top, FAddSpeakerButton.Width, ScaleValue(30));
  FIconDetails.SetBounds(LeftWidth + Margin * 2, Margin,
    Max(ScaleValue(100), W - LeftWidth - Margin * 3), Max(1, H - Margin * 2));
  W := FIconDetails.ClientWidth;
  H := FIconDetails.ClientHeight;
  FNameLabel.SetBounds(0, ScaleValue(8), ScaleValue(68), ScaleValue(20));
  FName.SetBounds(ScaleValue(72), ScaleValue(4), W - ScaleValue(72), ScaleValue(28));
  FSideLabel.SetBounds(0, ScaleValue(44), ScaleValue(68), ScaleValue(20));
  FSide.SetBounds(ScaleValue(72), ScaleValue(40), W - ScaleValue(72), ScaleValue(28));
  Compact := H < ScaleValue(400);
  if Compact then
  begin
    FIconFileLabel.SetBounds(0, ScaleValue(80), ScaleValue(68), ScaleValue(20));
    FIconFile.SetBounds(ScaleValue(72), ScaleValue(76),
      Max(ScaleValue(40), W - ScaleValue(200)), ScaleValue(28));
    FIconBrowse.SetBounds(W - ScaleValue(124), ScaleValue(74), ScaleValue(60), ScaleValue(30));
    FIconClear.SetBounds(W - ScaleValue(60), ScaleValue(74), ScaleValue(60), ScaleValue(30));
    Top := ScaleValue(112);
  end
  else
  begin
    FIconFileLabel.SetBounds(0, ScaleValue(80), W, ScaleValue(20));
    FIconFile.SetBounds(0, ScaleValue(104), Max(ScaleValue(40), W - ScaleValue(128)), ScaleValue(28));
    FIconBrowse.SetBounds(W - ScaleValue(124), ScaleValue(102), ScaleValue(60), ScaleValue(30));
    FIconClear.SetBounds(W - ScaleValue(60), ScaleValue(102), ScaleValue(60), ScaleValue(30));
    Top := ScaleValue(146);
  end;
  Row := Max(ScaleValue(34), Min(ScaleValue(60), (H - Top) div 3));
  // プレビューと、その直下の正方形ピッカーを同じ一辺で収める。
  ImageSize := Max(1, Min(ScaleValue(160), (H - Top - ScaleValue(52)) div 2));
  SliderLeft := Max(ImageSize + ScaleValue(30), ScaleValue(90)) + Margin;
  SliderHeight := Max(ScaleValue(18), Row - ScaleValue(22));
  FIconFrameLabel.SetBounds(0, Top, ImageSize, ScaleValue(20));
  FIconPreview.SetBounds(0, Top + ScaleValue(22), ImageSize, ImageSize);
  FIconColorLabel.SetBounds(0, FIconPreview.BoundsRect.Bottom + ScaleValue(8),
    ScaleValue(48), ScaleValue(20));
  FIconColorSwatch.SetBounds(ScaleValue(52), FIconColorLabel.Top,
    ScaleValue(22), ScaleValue(18));
  PickerTop := FIconColorLabel.Top + ScaleValue(22);
  FIconColorArea.SetBounds(0, PickerTop, ImageSize, ImageSize);
  FIconHueBar.SetBounds(ImageSize + ScaleValue(8), PickerTop, ScaleValue(18), ImageSize);
  FScaleLabel.SetBounds(SliderLeft, Top, W - SliderLeft, ScaleValue(20));
  FScale.SetBounds(SliderLeft, Top + ScaleValue(22), W - SliderLeft, SliderHeight);
  FIconXLabel.SetBounds(SliderLeft, Top + Row, W - SliderLeft, ScaleValue(20));
  FIconX.SetBounds(SliderLeft, Top + Row + ScaleValue(22), W - SliderLeft, SliderHeight);
  FIconYLabel.SetBounds(SliderLeft, Top + Row * 2, W - SliderLeft, ScaleValue(20));
  FIconY.SetBounds(SliderLeft, Top + Row * 2 + ScaleValue(22), W - SliderLeft, SliderHeight);
end;

procedure TFormMineSettings.NavigationChanged(Sender: TObject);
var
  I: Integer;
begin
  FPageHost.DisableAlign;
  try
    for I := 0 to 2 do FPages[I].Visible := I = FNavigation.ActiveIndex;
  finally
    FPageHost.EnableAlign;
  end;
  if FLayoutReady then Resize;
end;

destructor TFormMineSettings.Destroy;
begin
  if FTimer <> nil then FTimer.Enabled := False;
  FIconImage.Free;
  FRenderer.Free;
  FBuiltinNames.Free;
  FHistory.Free;
  inherited;
end;

procedure TFormMineSettings.BuildMessagePage(Parent: TWinControl);
begin
  FMessageList := TListBox.Create(Self);
  FMessageList.Parent := Parent;
  FMessageList.SetBounds(12, 12, 586, 210);
  FMessageList.Style := lbOwnerDrawFixed;
  FMessageList.ItemHeight := 28;
  FMessageList.OnDrawItem := DrawMessage;
  FMessageList.OnClick := LoadMessage;
  ApplySyncMusicStudioDarkListBox(FMessageList);
  ButtonAt(Parent, '追加', 12, 232, 90, AddMessage);
  ButtonAt(Parent, '削除', 110, 232, 90, DeleteMessage);
  ButtonAt(Parent, '上へ', 208, 232, 90, MoveMessage).Tag := -1;
  ButtonAt(Parent, '下へ', 306, 232, 90, MoveMessage).Tag := 1;
  LabelAt(Parent, '発言者', 12, 278);
  FSender := ComboAt(Parent, 80, 274, 270);
  FSender.OnChange := MessageChanged;
  LabelAt(Parent, '時刻', 368, 278);
  FTime := EditAt(Parent, 418, 274, 180);
  FTime.MaxLength := 32;
  FTime.OnChange := MessageChanged;
  LabelAt(Parent, '写真', 12, 318);
  FPhoto := EditAt(Parent, 80, 314, 318);
  FPhoto.ReadOnly := True;
  ButtonAt(Parent, '参照', 408, 312, 90, ChoosePhoto);
  ButtonAt(Parent, '解除', 508, 312, 90, ClearPhoto);
  LabelAt(Parent, '本文（写真と併用できます）', 12, 360);
  FText := TMemo.Create(Self);
  FText.Parent := Parent;
  FText.SetBounds(12, 386, 586, 160);
  FText.MaxLength := 4096;
  FText.ScrollBars := ssVertical;
  FText.WantReturns := True;
  FText.OnChange := MessageChanged;
  ApplySyncMusicStudioDarkMemo(FText);
  FMessageHint := LabelAt(Parent, '', 12, 559);
  FMessageHint.AutoSize := False;
  FMessageHint.SetBounds(12, 559, 586, 50);
  FMessageHint.WordWrap := True;
end;

procedure TFormMineSettings.BuildIconPage(Parent: TWinControl);
begin
  FSpeakerList := TListBox.Create(Self);
  FSpeakerList.Parent := Parent;
  FSpeakerList.OnClick := LoadSpeaker;
  ApplySyncMusicStudioDarkListBox(FSpeakerList);
  FAddSpeakerButton := ButtonAt(Parent, '追加', 0, 0, 60, AddSpeaker);
  FDeleteSpeakerButton := ButtonAt(Parent, '削除', 0, 0, 60, DeleteSpeaker);
  FIconDetails := TPanel.Create(Self);
  FIconDetails.Parent := Parent;
  FIconDetails.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(FIconDetails);
  FNameLabel := LabelAt(FIconDetails, 'キャラ名', 0, 0);
  FName := ComboAt(FIconDetails, 0, 0, 200);
  FName.Style := csDropDown;
  SetWindowTheme(FName.Handle, 'DarkMode_CFD', nil);
  FName.AutoComplete := False;
  FName.DropDownCount := 14;
  FName.MaxLength := 64;
  FName.Hint := '名前を入力、または最近使った名前・既存キャラから選択できます。';
  FName.ShowHint := True;
  RefreshCharacterNames;
  FName.OnChange := SpeakerChanged;
  FName.OnSelect := UseCharacter;
  FName.OnExit := CharacterNameExit;
  FName.OnDropDown := CharacterNamesDropDown;
  FSideLabel := LabelAt(FIconDetails, '自分／相手', 0, 0);
  FSide := ComboAt(FIconDetails, 0, 0, 200);
  FSide.Items.Add('相手側（左）');
  FSide.Items.Add('自分側（右）');
  FSide.OnChange := SpeakerChanged;
  FIconFileLabel := LabelAt(FIconDetails, '画像ファイル', 0, 0);
  FIconFile := EditAt(FIconDetails, 0, 0, 200);
  FIconFile.ReadOnly := True;
  FIconBrowse := ButtonAt(FIconDetails, '参照', 0, 0, 60, ChooseIcon);
  FIconClear := ButtonAt(FIconDetails, '解除', 0, 0, 60, ClearIcon);
  FIconFrameLabel := LabelAt(FIconDetails, 'アイコン枠', 0, 0);
  FIconPreview := TPaintBox.Create(Self);
  FIconPreview.Parent := FIconDetails;
  FIconPreview.OnPaint := PaintIcon;
  FIconColorSwatch := TPanel.Create(Self);
  FIconColorSwatch.Parent := FIconDetails;
  FIconColorSwatch.ParentBackground := False;
  FIconColorSwatch.BevelOuter := bvNone;
  FIconColorLabel := LabelAt(FIconDetails, '背景色', 0, 0);
  FIconColorArea := TColorPickerSVArea.Create(Self);
  FIconColorArea.Parent := FIconDetails;
  FIconColorArea.OnChange := IconColorChanged;
  FIconHueBar := TColorPickerHueBar.Create(Self);
  FIconHueBar.Parent := FIconDetails;
  FIconHueBar.OnChange := IconHueChanged;
  FScaleLabel := LabelAt(FIconDetails, '拡大率', 0, 0);
  FScale := SliderAt(FIconDetails, 0, 0, 160, 10, 1000, 100);
  FScale.OnChange := SpeakerChanged;
  FIconXLabel := LabelAt(FIconDetails, 'X 補正', 0, 0);
  FIconX := SliderAt(FIconDetails, 0, 0, 160, -200, 200, 0);
  FIconX.OnChange := SpeakerChanged;
  FIconYLabel := LabelAt(FIconDetails, 'Y 補正', 0, 0);
  FIconY := SliderAt(FIconDetails, 0, 0, 160, -200, 200, 0);
  FIconY.OnChange := SpeakerChanged;
end;

procedure TFormMineSettings.BuildSettingsPage(Parent: TWinControl);
begin
  LabelAt(Parent, 'トーク名', 12, 16);
  FTitle := EditAt(Parent, 12, 42, 480);
  FTitle.MaxLength := 128;
  FTitle.Text := FData.Title;
  FTitle.OnChange := SettingsChanged;
  LabelAt(Parent, 'スマホの方向', 12, 94);
  FOrientation := ComboAt(Parent, 12, 120, 200);
  FOrientation.Items.Add('縦向き');
  FOrientation.Items.Add('横向き');
  FOrientation.OnChange := SettingsChanged;
  LabelAt(Parent, 'スマホの色', 12, 172);
  FColorSwatch := TPanel.Create(Self);
  FColorSwatch.Parent := Parent;
  FColorSwatch.SetBounds(12, 198, 48, 30);
  FColorSwatch.BevelOuter := bvNone;
  FColorSwatch.ParentBackground := False;
  FColorButton := ButtonAt(Parent, '色を選ぶ', 72, 198, 140, ChoosePhoneColor);
  FSettingsHint := LabelAt(Parent, '方向と本体色はAviUtl2側の設定にも反映します。', 12, 254);
  FSettingsHint.AutoSize := False;
  FSettingsHint.SetBounds(12, 254, 480, 44);
  FSettingsHint.WordWrap := True;
end;

procedure TFormMineSettings.SettingsChanged(Sender: TObject);
begin
  if FLoading then Exit;
  FData.Title := FTitle.Text;
  FDirty := True;
end;

procedure TFormMineSettings.UpdatePhoneColor;
var
  R, G, B: Byte;
begin
  R := (FPhoneColor shr 16) and $FF;
  G := (FPhoneColor shr 8) and $FF;
  B := FPhoneColor and $FF;
  FColorSwatch.Color := RGB(R, G, B);
  FPreview.Invalidate;
end;

procedure TFormMineSettings.ChoosePhoneColor(Sender: TObject);
var
  Color: Cardinal;
begin
  Color := FPhoneColor and $FFFFFF;
  if not EditMineColor(Self, 'スマホの色', Color) then Exit;
  FPhoneColor := $FF000000 or Color;
  UpdatePhoneColor;
end;

procedure TFormMineSettings.IconColorChanged(Sender: TObject);
var
  I: Integer;
  Color: TColor;
begin
  if FLoading then Exit;
  I := FSpeakerList.ItemIndex;
  if I < 0 then Exit;
  Color := ColorToRGB(FIconColorArea.Color);
  FData.Speakers[I].IconBackground := (Cardinal(GetRValue(Color)) shl 16) or
    (Cardinal(GetGValue(Color)) shl 8) or GetBValue(Color);
  RememberCharacter;
  RefreshIcon;
  FDirty := True;
end;

procedure TFormMineSettings.IconHueChanged(Sender: TObject);
var
  Saturation, Value: Double;
begin
  if FLoading then Exit;
  FIconCurrentHue := ColorHue(FIconHueBar.Color);
  ColorToSv(FIconColorArea.Color, Saturation, Value);
  FIconColorArea.BaseColor := FIconHueBar.Color;
  FIconColorArea.Color := HsvToColor(FIconCurrentHue, Saturation, Value);
  IconColorChanged(Sender);
end;
function TFormMineSettings.MessageCaption(Index: Integer): string;
var
  Summary: string;
begin
  Summary := FData.Messages[Index].Text.Replace(#13, ' ').Replace(#10, ' ');
  if FData.Messages[Index].PhotoFile <> '' then Summary := '[写真] ' + Summary;
  Result := Format('%d〜%d → %d既読  %s  %s', [Index * 100, Index * 100 + 99,
    (Index + 1) * 100, SpeakerCaption(FData.Messages[Index].Speaker), Copy(Summary, 1, 72)]);
end;

procedure TFormMineSettings.RefreshLists(MessageIndex, SpeakerIndex: Integer);
var
  I: Integer;
begin
  FLoading := True;
  try
    FMessageList.Items.BeginUpdate;
    FSpeakerList.Items.BeginUpdate;
    try
      FMessageList.Clear;
      for I := 0 to High(FData.Messages) do FMessageList.Items.Add(MessageCaption(I));
      FSpeakerList.Clear;
      FSender.Clear;
      for I := 0 to High(FData.Speakers) do
      begin
        FSpeakerList.Items.Add(SpeakerCaption(I));
        FSender.Items.Add(SpeakerCaption(I));
      end;
      FMessageList.ItemIndex := Min(MessageIndex, High(FData.Messages));
      FSpeakerList.ItemIndex := EnsureRange(SpeakerIndex, 0, High(FData.Speakers));
      FStage.Max := Max(100, Length(FData.Messages) * 100);
    finally
      FSpeakerList.Items.EndUpdate;
      FMessageList.Items.EndUpdate;
    end;
  finally
    FLoading := False;
  end;
  LoadMessage(nil);
  LoadSpeaker(nil);
  FDirty := True;
end;

procedure TFormMineSettings.LoadMessage(Sender: TObject);
var
  I: Integer;
begin
  I := FMessageList.ItemIndex;
  FLoading := True;
  try
    FText.Enabled := I >= 0;
    FSender.Enabled := I >= 0;
    FTime.Enabled := I >= 0;
    FText.Clear;
    FPhoto.Clear;
    FTime.Clear;
    FSender.ItemIndex := -1;
    if I >= 0 then
    begin
      FText.Text := FData.Messages[I].Text;
      FPhoto.Text := FData.Messages[I].PhotoFile;
      FTime.Text := FData.Messages[I].TimeText;
      FSender.ItemIndex := FData.Messages[I].Speaker;
      FStage.Position := (I + 1) * 100;
    end;
  finally
    FLoading := False;
  end;
  UpdateMessageHint;
  FPreview.Invalidate;
end;

procedure TFormMineSettings.LoadSpeaker(Sender: TObject);
var
  I: Integer;
begin
  I := FSpeakerList.ItemIndex;
  if I < 0 then Exit;
  if FData.Speakers[I].CharacterName <> '' then
    FData.Speakers[I].IconFile := MineCharacterIconFile(FData.Speakers[I].CharacterName);
  FLoading := True;
  try
    FName.Text := FData.Speakers[I].Name;
    FSide.ItemIndex := Ord(FData.Speakers[I].Outgoing);
    FIconFile.Text := FData.Speakers[I].IconFile;
    FNameNeedsApply := False;
    FScale.Position := Round(FData.Speakers[I].IconScale);
    FIconX.Position := Round(FData.Speakers[I].IconX);
    FIconY.Position := Round(FData.Speakers[I].IconY);
  finally
    FLoading := False;
  end;
  if Sender <> nil then RememberCharacter;
  RefreshIcon;
end;

procedure TFormMineSettings.MessageChanged(Sender: TObject);
var
  I: Integer;
begin
  if FLoading then Exit;
  I := FMessageList.ItemIndex;
  if I >= 0 then
  begin
    if FSender.ItemIndex >= 0 then FData.Messages[I].Speaker := FSender.ItemIndex;
    FData.Messages[I].Text := FText.Text;
    FData.Messages[I].TimeText := FTime.Text;
    FMessageList.Items[I] := MessageCaption(I);
  end;
  UpdateMessageHint;
  FDirty := True;
end;

procedure TFormMineSettings.SpeakerChanged(Sender: TObject);
var
  I, J, Selected: Integer;
begin
  if FLoading then Exit;
  I := FSpeakerList.ItemIndex;
  if I < 0 then Exit;
  FData.Speakers[I].Name := FName.Text;
  FData.Speakers[I].Outgoing := FSide.ItemIndex = 1;
  FData.Speakers[I].IconScale := FScale.Position;
  FData.Speakers[I].IconX := FIconX.Position;
  FData.Speakers[I].IconY := FIconY.Position;
  if Sender = FName then FNameNeedsApply := True
  else RememberCharacter;
  FLoading := True;
  try
    Selected := FSender.ItemIndex;
    FSpeakerList.Items[I] := SpeakerCaption(I);
    FSender.Items[I] := SpeakerCaption(I);
    FSender.ItemIndex := Selected;
    for J := 0 to High(FData.Messages) do FMessageList.Items[J] := MessageCaption(J);
  finally
    FLoading := False;
  end;
  UpdateMessageHint;
  RefreshIcon;
  FDirty := True;
end;

procedure TFormMineSettings.AddMessage(Sender: TObject);
var
  I: Integer;
begin
  I := Length(FData.Messages);
  if I >= MINE_MAX_MESSAGES then Exit;
  SetLength(FData.Messages, I + 1);
  FData.Messages[I] := Default(TMineMessage);
  FData.Messages[I].Text := 'メッセージ';
  if FSender.ItemIndex >= 0 then FData.Messages[I].Speaker := FSender.ItemIndex;
  RefreshLists(I, FSpeakerList.ItemIndex);
  FText.SetFocus;
  FText.SelectAll;
end;

procedure TFormMineSettings.DeleteMessage(Sender: TObject);
var
  I: Integer;
begin
  I := FMessageList.ItemIndex;
  if I < 0 then Exit;
  Delete(FData.Messages, I, 1);
  RefreshLists(I, FSpeakerList.ItemIndex);
end;

procedure TFormMineSettings.MoveMessage(Sender: TObject);
var
  I, J: Integer;
  Message: TMineMessage;
begin
  I := FMessageList.ItemIndex;
  J := I + TButton(Sender).Tag;
  if (I < 0) or (J < 0) or (J >= Length(FData.Messages)) then Exit;
  Message := FData.Messages[I];
  FData.Messages[I] := FData.Messages[J];
  FData.Messages[J] := Message;
  RefreshLists(J, FSpeakerList.ItemIndex);
end;

procedure TFormMineSettings.AddSpeaker(Sender: TObject);
var
  I: Integer;
begin
  I := Length(FData.Speakers);
  if I >= MINE_MAX_SPEAKERS then Exit;
  SetLength(FData.Speakers, I + 1);
  FData.Speakers[I] := Default(TMineSpeaker);
  FData.Speakers[I].Name := '発言者 ' + IntToStr(I + 1);
  FData.Speakers[I].IconScale := 100;
  FData.Speakers[I].IconBackground := MINE_DEFAULT_ICON_BACKGROUND;
  RefreshLists(FMessageList.ItemIndex, I);
end;

procedure TFormMineSettings.DeleteSpeaker(Sender: TObject);
var
  I, J: Integer;
begin
  I := FSpeakerList.ItemIndex;
  if (I < 0) or (Length(FData.Speakers) <= 1) then Exit;
  for J := 0 to High(FData.Messages) do
    if FData.Messages[J].Speaker = I then
    begin
      MessageDlg('この発言者は会話で使用中です。先にメッセージの発言者を変更してください。',
        mtInformation, [mbOK], 0);
      Exit;
    end;
  Delete(FData.Speakers, I, 1);
  for J := 0 to High(FData.Messages) do
    if FData.Messages[J].Speaker > I then Dec(FData.Messages[J].Speaker);
  RefreshLists(FMessageList.ItemIndex, I);
end;

function TFormMineSettings.ChooseImage(out FileName: string): Boolean;
var
  Dialog: TOpenDialog;
  Image: TGPBitmap;
begin
  Result := False;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := '画像ファイル|*.png;*.jpg;*.jpeg;*.bmp;*.gif|すべてのファイル|*.*';
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
    if not Dialog.Execute then Exit;
    Image := LoadMinePicture(Dialog.FileName);
    try
      if Image = nil then
      begin
        MessageDlg('この画像を読み込めません。画像形式とサイズを確認してください。', mtError, [mbOK], 0);
        Exit;
      end;
      FileName := ExpandFileName(Dialog.FileName);
      Result := True;
    finally
      Image.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TFormMineSettings.ChoosePhoto(Sender: TObject);
var
  FileName: string;
  I: Integer;
begin
  I := FMessageList.ItemIndex;
  if (I < 0) or not ChooseImage(FileName) then Exit;
  FData.Messages[I].PhotoFile := FileName;
  FPhoto.Text := FileName;
  MessageChanged(nil);
end;

procedure TFormMineSettings.ClearPhoto(Sender: TObject);
var
  I: Integer;
begin
  I := FMessageList.ItemIndex;
  if I < 0 then Exit;
  FData.Messages[I].PhotoFile := '';
  FPhoto.Clear;
  MessageChanged(nil);
end;

procedure TFormMineSettings.ChooseIcon(Sender: TObject);
var
  FileName: string;
  I: Integer;
begin
  I := FSpeakerList.ItemIndex;
  if (I < 0) or not ChooseImage(FileName) then Exit;
  FData.Speakers[I].IconFile := FileName;
  FData.Speakers[I].CharacterName := '';
  FIconFile.Text := FileName;
  RememberCharacter;
  RefreshIcon;
  FDirty := True;
end;

procedure TFormMineSettings.ClearIcon(Sender: TObject);
var
  I: Integer;
begin
  I := FSpeakerList.ItemIndex;
  if I < 0 then Exit;
  FData.Speakers[I].IconFile := '';
  FData.Speakers[I].CharacterName := '';
  FIconFile.Clear;
  RememberCharacter;
  RefreshIcon;
  FDirty := True;
end;

procedure TFormMineSettings.UseCharacter(Sender: TObject);
var
  I: Integer;
  Name: string;
  Profile: TMineSpeaker;
begin
  if FLoading then Exit;
  I := FSpeakerList.ItemIndex;
  Name := Trim(FName.Text);
  if (I < 0) or (Name = '') then Exit;
  try
    if FHistory.Find(Name, Profile) then
    begin
      Profile.Outgoing := FData.Speakers[I].Outgoing;
      FData.Speakers[I] := Profile;
    end
    else
    begin
      FData.Speakers[I].Name := Name;
      if FBuiltinNames.IndexOf(Name) >= 0 then
      begin
        FData.Speakers[I].IconFile := MineCharacterIconFile(Name);
        FData.Speakers[I].CharacterName := Name;
        FData.Speakers[I].IconScale := 100;
        FData.Speakers[I].IconX := 0;
        FData.Speakers[I].IconY := 0;
      end;
    end;
    FNameNeedsApply := False;
    RememberCharacter;
    RefreshCharacterNames;
    LoadSpeaker(nil);
    SpeakerChanged(nil);
    RefreshIcon;
    FDirty := True;
  except
    on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFormMineSettings.CharacterNameExit(Sender: TObject);
begin
  if FNameNeedsApply then UseCharacter(Sender);
end;

procedure TFormMineSettings.CharacterNamesDropDown(Sender: TObject);
begin
  RefreshCharacterNames;
end;

procedure TFormMineSettings.RememberCharacter;
var
  I: Integer;
begin
  I := FSpeakerList.ItemIndex;
  if (I >= 0) and not FNameNeedsApply and (FData.Speakers[I].Name.Trim <> '') then
    FHistory.Remember(FData.Speakers[I]);
end;

procedure TFormMineSettings.RefreshCharacterNames;
var
  Text: string;
  Loading: Boolean;
begin
  Text := FName.Text;
  Loading := FLoading;
  FLoading := True;
  try
    FHistory.FillNames(FName.Items, FBuiltinNames);
    FName.Text := Text;
  finally
    FLoading := Loading;
  end;
end;

procedure TFormMineSettings.RefreshIcon;
var
  Color: Cardinal;
  Hue, Saturation, Value: Double;
begin
  if FIconFile.Text <> FIconImageFile then
  begin
    FreeAndNil(FIconImage);
    FIconImageFile := FIconFile.Text;
    FIconImage := LoadMinePicture(FIconImageFile);
  end;
  FScaleLabel.Caption := Format('拡大率 %d%%', [FScale.Position]);
  FIconXLabel.Caption := Format('X 補正 %d%%', [FIconX.Position]);
  FIconYLabel.Caption := Format('Y 補正 %d%%', [FIconY.Position]);
  FIconFile.Hint := FIconFile.Text;
  FIconFile.ShowHint := True;
  Color := FData.Speakers[FSpeakerList.ItemIndex].IconBackground;
  FIconColorSwatch.Color := RGB((Color shr 16) and $FF, (Color shr 8) and $FF, Color and $FF);
  ColorToHsv(FIconColorSwatch.Color, Hue, Saturation, Value);
  if (Saturation > 0.000001) and (Value > 0) then FIconCurrentHue := Hue;
  FIconHueBar.Color := HsvToColor(FIconCurrentHue, 1, 1);
  FIconColorArea.BaseColor := FIconHueBar.Color;
  FIconColorArea.Color := FIconColorSwatch.Color;
  FIconColorSwatch.Hint := '#' + IntToHex(Color, 6);
  FIconColorSwatch.ShowHint := True;
  FIconPreview.Invalidate;
end;

procedure TFormMineSettings.PaintIcon(Sender: TObject);
var
  Target: TGPGraphics;
  Size, Margin: Integer;
begin
  FIconPreview.Canvas.Brush.Color := $00404040;
  FIconPreview.Canvas.FillRect(FIconPreview.ClientRect);
  Margin := ScaleValue(6);
  Size := Min(FIconPreview.Width, FIconPreview.Height) - Margin * 2;
  Target := TGPGraphics.Create(FIconPreview.Canvas.Handle);
  try
    Target.SetSmoothingMode(SmoothingModeAntiAlias);
    Target.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    DrawMineIcon(Target, FIconImage, MakeRect(Single(Margin), Single(Margin), Single(Size), Single(Size)),
      FScale.Position, FIconX.Position, FIconY.Position, 255,
      FData.Speakers[FSpeakerList.ItemIndex].IconBackground);
  finally
    Target.Free;
  end;
end;

procedure TFormMineSettings.PaintPreview(Sender: TObject);
var
  Buffer: TBitmap;
  Target: TGPGraphics;
  W, H, X, Y, CellSize, Margin: Integer;
  Ratio: Double;
begin
  if FPreview.ClientRect.IsEmpty then Exit;
  Buffer := TBitmap.Create;
  try
    Buffer.SetSize(FPreview.Width, FPreview.Height);
    CellSize := Max(1, ScaleValue(16));
    Margin := ScaleValue(20);
    for Y := 0 to (Buffer.Height - 1) div CellSize do
      for X := 0 to (Buffer.Width - 1) div CellSize do
      begin
        if Odd(X + Y) then Buffer.Canvas.Brush.Color := $00353535
        else Buffer.Canvas.Brush.Color := $003D3D3D;
        Buffer.Canvas.FillRect(Rect(X * CellSize, Y * CellSize,
          (X + 1) * CellSize, (Y + 1) * CellSize));
      end;
    MinePhoneSize(FOrientation.ItemIndex, W, H);
    Ratio := Min(Max(1, FPreview.Width - Margin) / W,
      Max(1, FPreview.Height - Margin) / H);
    W := Max(1, Round(W * Ratio));
    H := Max(1, Round(H * Ratio));
    X := (FPreview.Width - W) div 2;
    Y := (FPreview.Height - H) div 2;
    Target := TGPGraphics.Create(Buffer.Canvas.Handle);
    try
      FRenderer.Draw(Target, Rect(X, Y, X + W, Y + H), FStage.Position, FPhoneColor);
    finally
      Target.Free;
    end;
    FPreview.Canvas.Draw(0, 0, Buffer);
  finally
    Buffer.Free;
  end;
end;

procedure TFormMineSettings.PreviewChanged(Sender: TObject);
var
  I, Step: Integer;
begin
  FStageLabel.Caption := Format('段階 %d / %d', [FStage.Position, Length(FData.Messages) * 100]);
  I := FStage.Position div 100;
  Step := FStage.Position mod 100;
  if FStage.Position = 0 then FStatus.Caption := '会話なし'
  else if Step = 0 then FStatus.Caption := Format('%d件目が既読', [I])
  else if I < Length(FData.Messages) then
  begin
    if FData.Speakers[FData.Messages[I].Speaker].Outgoing then
      if Step <= 85 then FStatus.Caption := Format('%d件目：自分が入力中', [I + 1])
      else FStatus.Caption := Format('%d件目：自分が送信中', [I + 1])
    else FStatus.Caption := Format('%d件目：相手から受信中', [I + 1]);
  end;
  if Sender = FOrientation then FDirty := True;
  FPreview.Invalidate;
end;

procedure TFormMineSettings.Tick(Sender: TObject);
begin
  if not FDirty then Exit;
  FDirty := False;
  try
    FRenderer.Prepare(FData, FOrientation.ItemIndex);
    PreviewChanged(nil);
  except
    on E: Exception do FStatus.Caption := E.Message;
  end;
end;

procedure TFormMineSettings.CloseSettings(Sender: TObject);
begin
  Close;
end;

procedure TFormMineSettings.ConfirmClose(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FClosedCommitted;
  if CanClose then Exit;
  try
    CharacterNameExit(nil);
    FData.Validate;
    if FNameNeedsApply then Exit;
    FResultJSON := FData.ToJSON;
    RememberCharacter;
    FHistory.Save;
    FClosedCommitted := True;
    CanClose := True;
  except
    on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

function EditMineSettings(var JSON: string; var Orientation: Integer; var PhoneColor: Cardinal): Boolean;
var
  Form: TFormMineSettings;
begin
  Form := TFormMineSettings.CreateForConversation(JSON, Orientation, PhoneColor);
  try
    Form.ShowModal;
    Result := Form.FClosedCommitted;
    if Result then
    begin
      JSON := Form.FResultJSON;
      Orientation := Form.FOrientation.ItemIndex;
      PhoneColor := Form.FPhoneColor;
    end;
  finally
    Form.Free;
  end;
end;

procedure CheckMineInline(DPI: Integer; Compact: Boolean; const Folder: string);
var
  Form: TFormMineSettings;
  B: TBitmap;
  PNG: TPngImage;
  Profile: TMineSpeaker;
  History: TMineCharacterHistory;
  JSON: string;
  Checks: Integer;
  procedure Check(Value: Boolean; const Text: string);
  begin
    if not Value then raise Exception.CreateFmt('%d DPI compact=%s: %s',
      [DPI, BoolToStr(Compact, True), Text]);
    Inc(Checks);
  end;
  procedure Fits(Control: TControl);
  begin
    Check((Control.Left >= 0) and (Control.Top >= 0) and
      (Control.BoundsRect.Right <= Control.Parent.ClientWidth + 1) and
      (Control.BoundsRect.Bottom <= Control.Parent.ClientHeight + 1), Control.ClassName + ' fits');
  end;
begin
  Checks := 0;
  Form := TFormMineSettings.CreateForConversation(
    '{"messages":[{"text":"背景色をその場で変更します。","speaker":0}]}', 0, $FF202428);
  try
    Form.FTimer.Enabled := False;
    Form.Show;
    Form.ScaleForPPI(DPI);
    if Compact then
    begin
      Form.ClientWidth := Form.ScaleValue(880);
      Form.ClientHeight := Form.ScaleValue(500);
    end
    else
    begin
      Form.ClientWidth := Form.ScaleValue(1040);
      Form.ClientHeight := Form.ScaleValue(740);
    end;
    Form.FitToWorkArea;
    Form.FNavigation.ActiveIndex := 1;
    Form.NavigationChanged(nil);
    Form.Resize;
    Fits(Form.FIconDetails);
    Fits(Form.FName);
    Fits(Form.FSide);
    Fits(Form.FIconFile);
    Fits(Form.FIconBrowse);
    Fits(Form.FIconClear);
    Fits(Form.FIconPreview);
    Fits(Form.FIconColorLabel);
    Fits(Form.FIconColorSwatch);
    Fits(Form.FIconColorArea);
    Fits(Form.FIconHueBar);
    Fits(Form.FScale);
    Fits(Form.FIconX);
    Fits(Form.FIconY);
    Check(Form.FIconColorArea.Parent = Form.FIconDetails, 'picker embedded in icon page');
    Check(Form.FIconColorArea.Width = Form.FIconColorArea.Height, 'SV square');
    Check(Form.FIconColorArea.Width > Form.ScaleValue(36), 'picker usable size');
    Check(Form.FIconColorArea.Top > Form.FIconPreview.BoundsRect.Bottom, 'picker below icon');
    Check(Form.FIconHueBar.Height = Form.FIconColorArea.Height, 'hue same height');
    Check(Form.FIconHueBar.BoundsRect.Right < Form.FScale.Left, 'picker beside sliders');
    Check((Form.FIconFileLabel.BoundsRect.Right < Form.FIconFile.Left) or (Form.FIconFileLabel.BoundsRect.Bottom <= Form.FIconFile.Top),
      'file label precedes input or separate row');
    Form.FIconColorArea.Color := clBlack;
    Form.IconColorChanged(nil);
    Check(Form.FData.Speakers[0].IconBackground = 0, 'black immediately stored');
    Form.FIconHueBar.Color := clLime;
    Form.IconHueChanged(nil);
    Check(Form.FData.Speakers[0].IconBackground = 0, 'hue preserves black');
    TAreaAccess(Form.FIconColorArea).MouseDown(mbLeft, [], Form.FIconColorArea.Width - 1, 0);
    Check(Form.FData.Speakers[0].IconBackground = $00FF00, 'direct mouse color stored');
    Check(Form.FIconColorSwatch.Color = clLime, 'swatch updated');
    Form.FSpeakerList.ItemIndex := 1;
    Form.LoadSpeaker(nil);
    Check(Form.FData.Speakers[1].IconBackground = MINE_DEFAULT_ICON_BACKGROUND, 'other character unchanged');
    Form.FIconColorArea.Color := clBlue;
    Form.IconColorChanged(nil);
    Form.FSpeakerList.ItemIndex := 0;
    Form.LoadSpeaker(nil);
    Check(Form.FIconColorArea.Color = clLime, 'switch restores picker');
    Check(Form.FData.Speakers[1].IconBackground = $0000FF, 'second character independent');
    Form.FData.Speakers[0].CharacterName := '東北きりたん';
    Form.LoadSpeaker(nil);
    Form.FDirty := True;
    Form.Tick(nil);
    Form.Update;
    Application.ProcessMessages;
    B := Form.GetFormImage;
    try
      PNG := TPngImage.Create;
      try
        PNG.Assign(B);
        PNG.SaveToFile(TPath.Combine(Folder, Format('inline-%d-%s.png',
          [DPI, BoolToStr(Compact, True)])));
      finally PNG.Free; end;
    finally B.Free; end;
    Check(Form.CloseQuery, 'close saves');
    JSON := Form.FResultJSON;
    Check(TMineConversation.FromJSON(JSON).Speakers[0].IconBackground = $00FF00, 'closed JSON has direct color');
    History := TMineCharacterHistory.Create(Form.FHistory.Folder);
    try
      History.Load;
      Check(History.Find('相手', Profile) and (Profile.IconBackground = $00FF00), 'history stores direct color');
    finally History.Free; end;
    Writeln(Format('PASS %d DPI compact=%s: %d checks, square=%dx%d',
      [DPI, BoolToStr(Compact, True), Checks, Form.FIconColorArea.Width, Form.FIconColorArea.Height]));
  finally Form.Free; end;
end;

end.