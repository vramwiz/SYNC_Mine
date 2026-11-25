unit SYNC_MINE_TimingEditor;

// 会話全体または選択した発言へ、時刻と演出を一括適用する設定を受け取る。

interface

uses SYNC_MINE_Conversation;

type
  TMineBatchTiming = record
    SelectedOnly, ChangeTimes, ChangeAppearance: Boolean;
    StartMS, IntervalMS: Integer;
    Outgoing, Incoming: TMineAppearance;
  end;

function EditMineTiming(SelectionCount: Integer; var Settings: TMineBatchTiming): Boolean;
function TryMineMilliseconds(const Text: string; out Milliseconds: Integer): Boolean;

implementation

uses System.Math, System.SysUtils, System.UITypes, Winapi.Windows,
  Vcl.Controls, Vcl.Dialogs, Vcl.Forms, Vcl.StdCtrls,
  SYNC_MusicStudio_DarkTheme, SYNC_MINE_DarkControls, SYNC_MINE_Timeline;

function TryMineMilliseconds(const Text: string; out Milliseconds: Integer): Boolean;
var
  Seconds: Double;
begin
  Result := TryStrToFloat(Text.Trim, Seconds, TFormatSettings.Invariant) and
    not IsNan(Seconds) and not IsInfinite(Seconds) and (Seconds >= 0) and
    (Seconds <= MINE_MAX_MESSAGE_MS / 1000);
  if Result then Milliseconds := Round(Seconds * 1000);
end;

function EditMineTiming(SelectionCount: Integer; var Settings: TMineBatchTiming): Boolean;
var
  Form: TForm;
  Scope, Outgoing, Incoming: TComboBox;
  ChangeTimes, ChangeAppearance: TCheckBox;
  StartAt, Interval: TEdit;
  StartMS, IntervalMS: Integer;

  procedure LabelAt(const Text: string; X, Y: Integer);
  var
    Item: TLabel;
  begin
    Item := TLabel.Create(Form);
    Item.Parent := Form;
    Item.Caption := Text;
    Item.SetBounds(X, Y, 124, 22);
    Item.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  end;

  function ComboAt(Y: Integer): TComboBox;
  begin
    Result := TComboBox.Create(Form);
    Result.Parent := Form;
    Result.Style := csDropDownList;
    Result.SetBounds(144, Y, 196, 28);
  end;

  function EditAt(Y, Milliseconds: Integer): TEdit;
  begin
    Result := TEdit.Create(Form);
    Result.Parent := Form;
    Result.SetBounds(144, Y, 196, 28);
    Result.MaxLength := 12;
    Result.Text := MineSecondsText(Milliseconds);
    ApplySyncMusicStudioDarkEdit(Result);
  end;

  function CheckAt(const Text: string; Y: Integer; Checked: Boolean): TCheckBox;
  begin
    Result := TCheckBox.Create(Form);
    Result.Parent := Form;
    Result.SetBounds(16, Y, 324, 24);
    Result.Caption := Text;
    Result.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
    Result.Checked := Checked;
  end;

  procedure AddButton(const Text: string; X, ModalResult: Integer);
  var
    Button: TButton;
  begin
    Button := TMineDarkButton.Create(Form);
    Button.Parent := Form;
    Button.SetBounds(X, 270, 96, 30);
    Button.Caption := Text;
    Button.ModalResult := ModalResult;
    Button.Default := ModalResult = mrOk;
    Button.Cancel := ModalResult = mrCancel;
    ApplySyncMusicStudioDarkButton(Button);
  end;

begin
  Result := False;
  Form := TForm.CreateNew(nil);
  try
    Form.Caption := 'タイミングと演出の一括設定';
    Form.BorderStyle := bsDialog;
    Form.Position := poMainFormCenter;
    Form.Font.PixelsPerInch := USER_DEFAULT_SCREEN_DPI;
    Form.Font.Name := 'Yu Gothic UI';
    Form.Font.Size := 10;
    Form.ClientWidth := 356;
    Form.ClientHeight := 316;
    ApplySyncMusicStudioDarkForm(Form);
    LabelAt('適用先', 16, 20);
    Scope := ComboAt(16);
    Scope.Items.Add('会話全体');
    if SelectionCount > 0 then Scope.Items.Add(Format('選択した発言 (%d件)', [SelectionCount]));
    Scope.ItemIndex := Ord(Settings.SelectedOnly and (SelectionCount > 0));
    Scope.Enabled := SelectionCount > 0;
    ChangeTimes := CheckAt('タイミングを変更', 52, Settings.ChangeTimes);
    LabelAt('開始位置 (秒)', 32, 86);
    StartAt := EditAt(82, Settings.StartMS);
    LabelAt('発言間隔 (秒)', 32, 122);
    Interval := EditAt(118, Settings.IntervalMS);
    ChangeAppearance := CheckAt('演出を変更', 154, Settings.ChangeAppearance);
    LabelAt('自分側', 32, 188);
    Outgoing := ComboAt(184);
    Outgoing.Items.AddStrings(['即表示', '短いフェード', '入力して送信']);
    Outgoing.ItemIndex := Ord(Settings.Outgoing);
    LabelAt('相手側', 32, 224);
    Incoming := ComboAt(220);
    Incoming.Items.AddStrings(['即表示', '短いフェード']);
    Incoming.ItemIndex := Ord(Settings.Incoming);
    AddButton('キャンセル', 140, mrCancel);
    AddButton('適用', 244, mrOk);
    Form.ScaleForPPI(Form.CurrentPPI);
    while Form.ShowModal = mrOk do
    begin
      if ChangeTimes.Checked and (not TryMineMilliseconds(StartAt.Text, StartMS) or
        not TryMineMilliseconds(Interval.Text, IntervalMS)) then
      begin
        MessageDlg('開始位置と発言間隔には、0以上86400未満の秒数を入力してください。', mtError, [mbOK], 0);
        Continue;
      end;
      Settings.SelectedOnly := Scope.ItemIndex = 1;
      Settings.ChangeTimes := ChangeTimes.Checked;
      Settings.ChangeAppearance := ChangeAppearance.Checked;
      if Settings.ChangeTimes then
      begin
        Settings.StartMS := StartMS;
        Settings.IntervalMS := IntervalMS;
      end;
      Settings.Outgoing := TMineAppearance(Outgoing.ItemIndex);
      Settings.Incoming := TMineAppearance(Incoming.ItemIndex);
      Exit(Settings.ChangeTimes or Settings.ChangeAppearance);
    end;
  finally
    Form.Free;
  end;
end;

end.
