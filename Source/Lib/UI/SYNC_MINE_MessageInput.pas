unit SYNC_MINE_MessageInput;

// IME確定と本文の改行を区別し、発言単位のキーボード操作をフォームへ渡す。

interface

uses
  Winapi.Messages, System.Classes, Vcl.Controls, Vcl.StdCtrls;

type
  TMineMessageCommand = (mmNext, mmPrevious, mmFollowing, mmDeletePrevious,
    mmDeleteFollowing, mmRestoreDeleted, mmSpeaker1, mmSpeaker2, mmSpeaker3,
    mmSpeaker4, mmSpeaker5, mmSpeaker6, mmSpeaker7, mmSpeaker8, mmSpeaker9);
  TMineMessageCommandEvent = procedure(Sender: TObject; Command: TMineMessageCommand;
    var Handled: Boolean) of object;

  TMineMessageMemo = class(TMemo)
  private
    FComposing, FIMEAccepting: Boolean;
    FSuppressedChar: Char;
    FDiscardShortcutChar: Boolean;
    FBackspaceRepeated: Boolean;
    FOnCommand: TMineMessageCommandEvent;
    function GetComposing: Boolean;
    function SendCommand(Command: TMineMessageCommand): Boolean;
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
  public
    property Composing: Boolean read GetComposing;
    property OnCommand: TMineMessageCommandEvent read FOnCommand write FOnCommand;
  end;

implementation

uses
  Winapi.Windows, Winapi.Imm;

function TMineMessageMemo.GetComposing: Boolean;
var
  Context: HIMC;
begin
  Result := FComposing or FIMEAccepting;
  if Result or not HandleAllocated then Exit;
  Context := ImmGetContext(Handle);
  if Context = 0 then Exit;
  try
    Result := ImmGetCompositionStringW(Context, GCS_COMPSTR, nil, 0) > 0;
  finally
    ImmReleaseContext(Handle, Context);
  end;
end;

procedure TMineMessageMemo.WndProc(var Message: TMessage);
begin
  case Message.Msg of
    WM_IME_STARTCOMPOSITION:
      begin
        FComposing := True;
        FIMEAccepting := False;
      end;
    WM_IME_ENDCOMPOSITION:
      begin
        // TSFではIME_KEYDOWNを経由せず確定する場合もある。
        if GetKeyState(VK_RETURN) < 0 then FIMEAccepting := True;
        FComposing := False;
      end;
    WM_IME_KEYDOWN:
      if FComposing and (Message.WParam = VK_RETURN) then FIMEAccepting := True;
    WM_KEYDOWN:
      begin
        FBackspaceRepeated := (Message.LParam and $40000000) <> 0;
        if (Message.WParam <> VK_RETURN) and (Message.WParam <> VK_PROCESSKEY) then
          FIMEAccepting := False;
      end;
    WM_KILLFOCUS:
      begin
        FComposing := False;
        FIMEAccepting := False;
      end;
  end;
  inherited;
  if (Message.Msg = WM_KEYUP) or (Message.Msg = WM_IME_KEYUP) then
    if (Message.WParam = VK_RETURN) or (Message.WParam = VK_PROCESSKEY) then
      FIMEAccepting := False;
end;

function TMineMessageMemo.SendCommand(Command: TMineMessageCommand): Boolean;
begin
  Result := False;
  if Assigned(FOnCommand) then FOnCommand(Self, Command, Result);
end;

procedure TMineMessageMemo.KeyDown(var Key: Word; Shift: TShiftState);
var
  Handled: Boolean;
  Suppressed: Char;
begin
  FSuppressedChar := #0;
  FDiscardShortcutChar := False;
  if Composing or (Key = VK_PROCESSKEY) then
  begin
    inherited;
    Exit;
  end;
  Handled := False;
  Suppressed := #0;
  if not (ssAlt in Shift) then
    case Key of
      VK_RETURN:
        if Shift = [] then
        begin
          Handled := SendCommand(mmNext);
          Suppressed := #13;
        end;
      VK_UP:
        if Shift = [ssCtrl] then Handled := SendCommand(mmPrevious);
      VK_DOWN:
        if Shift = [ssCtrl] then Handled := SendCommand(mmFollowing);
      VK_BACK:
        if (Shift = []) and (Text = '') and (SelLength = 0) then
        begin
          // 長押しで本文を消し切った時は行を残し、次に押したBackspaceで削除する。
          if FBackspaceRepeated then Handled := True
          else Handled := SendCommand(mmDeletePrevious);
          Suppressed := #8;
        end;
      Ord('Z'):
        if Shift = [ssCtrl] then
        begin
          Handled := SendCommand(mmRestoreDeleted);
          Suppressed := #26;
        end;
      Ord('1')..Ord('9'), VK_NUMPAD1..VK_NUMPAD9:
        if Shift = [ssCtrl] then
        begin
          if Key >= VK_NUMPAD1 then
            Handled := SendCommand(TMineMessageCommand(Ord(mmSpeaker1) + Key - VK_NUMPAD1))
          else Handled := SendCommand(TMineMessageCommand(Ord(mmSpeaker1) + Key - Ord('1')));
          // Ctrl+数字で発生する制御文字も本文へ挿入しない。
          FDiscardShortcutChar := Handled;
        end;
    end;
  if Handled then
  begin
    FSuppressedChar := Suppressed;
    Key := 0;
  end;
  inherited;
end;

procedure TMineMessageMemo.KeyPress(var Key: Char);
begin
  // 先行するKeyDownで発言を切り替えたキーを、新しい本文へ流さない。
  if FDiscardShortcutChar or ((FSuppressedChar <> #0) and (Key = FSuppressedChar)) then
  begin
    Key := #0;
    FSuppressedChar := #0;
    FDiscardShortcutChar := False;
  end;
  inherited;
end;

end.
