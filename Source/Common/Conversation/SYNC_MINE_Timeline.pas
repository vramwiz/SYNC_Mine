unit SYNC_MINE_Timeline;

// オブジェクト内の表示時刻、吹き出し演出、打鍵時刻を映像・音声で共有する。

interface

uses SYNC_MINE_Conversation;

const
  MINE_FADE_MS = 150;
  MINE_READ_MS = 300;

// 再生順に複製する。同時刻の発言は編集リストの順序を保つ。
function OrderedMineConversation(const Data: TMineConversation): TMineConversation;
function MineVisibleCount(const Data: TMineConversation; TimeMS: Double): Integer;
function MineReveal(const Message: TMineMessage; TimeMS: Double): Single;
function MineTypingDuration(const Data: TMineConversation; Index: Integer): Integer;
function MineTypingText(const Text: string): string;
function MineCharacterCount(const Text: string): Integer;
function MineTypedPrefix(const Text: string; Count: Integer): string;
function MinePreviewLimit(const Data: TMineConversation): Integer;
function MineSecondsText(Milliseconds: Integer): string;

implementation

uses System.Generics.Collections, System.Generics.Defaults, System.Math, System.SysUtils;

function OrderedMineConversation(const Data: TMineConversation): TMineConversation;
var
  Order: TArray<Integer>;
  Messages: TArray<TMineMessage>;
  I: Integer;
begin
  Result := Data;
  Messages := Data.Messages;
  SetLength(Order, Length(Messages));
  for I := 0 to High(Order) do Order[I] := I;
  TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
    function(const Left, Right: Integer): Integer
    begin
      Result := Messages[Left].ShowMS - Messages[Right].ShowMS;
      if Result = 0 then Result := Left - Right;
    end));
  Result.Messages := nil;
  SetLength(Result.Messages, Length(Messages));
  for I := 0 to High(Order) do Result.Messages[I] := Messages[Order[I]];
end;

function MineVisibleCount(const Data: TMineConversation; TimeMS: Double): Integer;
var
  LowIndex, HighIndex, Middle: Integer;
begin
  LowIndex := 0;
  HighIndex := Length(Data.Messages);
  while LowIndex < HighIndex do
  begin
    Middle := (LowIndex + HighIndex) div 2;
    if Data.Messages[Middle].ShowMS <= TimeMS then LowIndex := Middle + 1
    else HighIndex := Middle;
  end;
  Result := LowIndex;
end;

function MineReveal(const Message: TMineMessage; TimeMS: Double): Single;
var
  Fraction: Double;
begin
  if Message.Appearance = maInstant then Exit(1);
  Fraction := EnsureRange((TimeMS - Message.ShowMS) / MINE_FADE_MS, 0.0, 1.0);
  Result := Fraction * Fraction * (3 - 2 * Fraction);
end;

function MineTypingDuration(const Data: TMineConversation; Index: Integer): Integer;
var
  Message: TMineMessage;
  Earliest: Integer;
begin
  Message := Data.Messages[Index];
  if (Message.Appearance <> maTyping) or not Data.Speakers[Message.Speaker].Outgoing then Exit(0);
  Earliest := 0;
  if Index > 0 then Earliest := Data.Messages[Index - 1].ShowMS;
  Result := Min(Message.ShowMS - Earliest, EnsureRange(Length(Message.Text) * 42, 220, 900));
end;

function MineTypingText(const Text: string): string;
begin
  Result := Text.Replace(#13#10, ' ').Replace(#13, ' ').Replace(#10, ' ');
end;

procedure AdvanceCharacter(const Text: string; var Index: Integer);
begin
  if (Index < Length(Text)) and (Ord(Text[Index]) >= $D800) and
    (Ord(Text[Index]) <= $DBFF) and (Ord(Text[Index + 1]) >= $DC00) and
    (Ord(Text[Index + 1]) <= $DFFF) then Inc(Index);
  Inc(Index);
end;

function MineCharacterCount(const Text: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(Text) do
  begin
    AdvanceCharacter(Text, I);
    Inc(Result);
  end;
end;

function MineTypedPrefix(const Text: string; Count: Integer): string;
var
  I: Integer;
begin
  I := 1;
  while (Count > 0) and (I <= Length(Text)) do
  begin
    AdvanceCharacter(Text, I);
    Dec(Count);
  end;
  Result := Copy(Text, 1, I - 1);
end;

function MinePreviewLimit(const Data: TMineConversation): Integer;
var
  Message: TMineMessage;
begin
  Result := 1000;
  for Message in Data.Messages do Result := Max(Result, Message.ShowMS + 500);
end;

function MineSecondsText(Milliseconds: Integer): string;
begin
  Result := Format('%.3f', [Milliseconds / 1000], TFormatSettings.Invariant);
end;

end.
