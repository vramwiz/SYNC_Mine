unit SYNC_MINE_Conversation;

// 会話・画像参照・アイコンの補正値を検証し、AviUtl2 の文字列項目へ保存する。

interface

const
  MINE_MAX_MESSAGES = 1000;
  MINE_MAX_SPEAKERS = 64;
  MINE_DEFAULT_ICON_BACKGROUND = $00E2E8ED;

type
  TMineSpeaker = record
    Name, IconFile, CharacterName: string;
    Outgoing: Boolean;
    IconScale, IconX, IconY: Double;
    IconBackground: Cardinal; // RGB、アルファなし。円形枠の透明部分を埋める。
  end;

  TMineMessage = record
    Speaker: Integer;
    Text, TimeText, PhotoFile: string;
  end;

  TMineConversation = record
    Title: string;
    BackgroundColor, TextColor, OutgoingColor, IncomingColor: Cardinal;
    Speakers: TArray<TMineSpeaker>;
    Messages: TArray<TMineMessage>;
    class function NewConversation: TMineConversation; static;
    // 空文字列と旧土台の {} は新規会話。不正なデータは例外にする。
    class function FromJSON(const Text: string): TMineConversation; static;
    procedure Validate;
    function ToJSON: string;
  end;

implementation

uses
  System.Generics.Collections, System.JSON, System.Math, System.SysUtils;

class function TMineConversation.NewConversation: TMineConversation;
begin
  Result := Default(TMineConversation);
  Result.Title := 'トーク';
  Result.BackgroundColor := $8DA5BD;
  Result.TextColor := $373E49;
  Result.OutgoingColor := $8DEB78;
  Result.IncomingColor := $FFFFFF;
  SetLength(Result.Speakers, 2);
  Result.Speakers[0].Name := '相手';
  Result.Speakers[0].IconScale := 100;
  Result.Speakers[0].IconBackground := MINE_DEFAULT_ICON_BACKGROUND;
  Result.Speakers[1].Name := '自分';
  Result.Speakers[1].Outgoing := True;
  Result.Speakers[1].IconScale := 100;
  Result.Speakers[1].IconBackground := MINE_DEFAULT_ICON_BACKGROUND;
end;

procedure TMineConversation.Validate;
var
  Speaker: TMineSpeaker;
  Message: TMineMessage;
begin
  if (BackgroundColor > $FFFFFF) or (TextColor > $FFFFFF) or
    (OutgoingColor > $FFFFFF) or (IncomingColor > $FFFFFF) then
    raise Exception.Create('会話の配色が不正です。');
  if Length(Title) > 128 then raise Exception.Create('トーク名は128文字以内にしてください。');
  if (Length(Speakers) < 1) or (Length(Speakers) > MINE_MAX_SPEAKERS) then
    raise Exception.Create('発言者は1～64人にしてください。');
  if Length(Messages) > MINE_MAX_MESSAGES then
    raise Exception.Create('メッセージは1000件以内にしてください。');
  for Speaker in Speakers do
  begin
    if Speaker.IconBackground > $FFFFFF then
      raise Exception.Create('アイコンの背景色が不正です。');
    if (Speaker.Name.Trim = '') or (Length(Speaker.Name) > 64) then
      raise Exception.Create('表示名は1～64文字にしてください。');
    if (Length(Speaker.IconFile) > 32767) or (Length(Speaker.CharacterName) > 128) then
      raise Exception.Create('アイコンの参照名が長すぎます。');
    if IsNan(Speaker.IconScale) or IsInfinite(Speaker.IconScale) or
      (Speaker.IconScale < 10) or (Speaker.IconScale > 1000) or
      IsNan(Speaker.IconX) or IsInfinite(Speaker.IconX) or (Abs(Speaker.IconX) > 200) or
      IsNan(Speaker.IconY) or IsInfinite(Speaker.IconY) or (Abs(Speaker.IconY) > 200) then
      raise Exception.Create('アイコン補正は倍率10～1000%、X・Yは-200～200%にしてください。');
  end;
  for Message in Messages do
  begin
    if (Message.Speaker < 0) or (Message.Speaker >= Length(Speakers)) then
      raise Exception.Create('メッセージの発言者が見つかりません。');
    if (Length(Message.Text) > 4096) or (Length(Message.TimeText) > 32) or
      (Length(Message.PhotoFile) > 32767) then
      raise Exception.Create('本文は4096文字、時刻は32文字以内にしてください。');
  end;
end;

class function TMineConversation.FromJSON(const Text: string): TMineConversation;
var
  Value: TJSONValue;
  Root, Item, Colors: TJSONObject;
  Items: TJSONArray;
  I: Integer;
begin
  Result := NewConversation;
  if Text.Trim = '' then Exit;
  if Length(Text) > 8 * 1024 * 1024 then raise Exception.Create('会話データが大きすぎます。');
  Value := TJSONObject.ParseJSONValue(Text);
  try
    if not (Value is TJSONObject) then raise Exception.Create('会話データのJSONが不正です。');
    Root := TJSONObject(Value);
    if Root.GetValue<Integer>('version', 1) <> 1 then
      raise Exception.Create('この会話データのバージョンには対応していません。');
    Result.Title := Root.GetValue<string>('title', Result.Title);
    if Root.TryGetValue<TJSONObject>('colors', Colors) then
    begin
      Result.BackgroundColor := Colors.GetValue<Integer>('background', Result.BackgroundColor);
      Result.TextColor := Colors.GetValue<Integer>('text', Result.TextColor);
      Result.OutgoingColor := Colors.GetValue<Integer>('outgoing', Result.OutgoingColor);
      Result.IncomingColor := Colors.GetValue<Integer>('incoming', Result.IncomingColor);
    end;
    if Root.TryGetValue<TJSONArray>('speakers', Items) then
    begin
      if (Items.Count < 1) or (Items.Count > MINE_MAX_SPEAKERS) then
        raise Exception.Create('発言者の件数が不正です。');
      SetLength(Result.Speakers, Items.Count);
      for I := 0 to Items.Count - 1 do
      begin
        if not (Items[I] is TJSONObject) then raise Exception.Create('発言者の形式が不正です。');
        Item := TJSONObject(Items[I]);
        Result.Speakers[I].Name := Item.GetValue<string>('name', '相手');
        Result.Speakers[I].IconFile := Item.GetValue<string>('icon', '');
        Result.Speakers[I].CharacterName := Item.GetValue<string>('character', '');
        Result.Speakers[I].Outgoing := Item.GetValue<Boolean>('outgoing', False);
        Result.Speakers[I].IconScale := Item.GetValue<Double>('scale', 100);
        Result.Speakers[I].IconX := Item.GetValue<Double>('x', 0);
        Result.Speakers[I].IconY := Item.GetValue<Double>('y', 0);
        Result.Speakers[I].IconBackground := Item.GetValue<Integer>('background', MINE_DEFAULT_ICON_BACKGROUND);
      end;
    end;
    if Root.TryGetValue<TJSONArray>('messages', Items) then
    begin
      if Items.Count > MINE_MAX_MESSAGES then raise Exception.Create('メッセージが1000件を超えています。');
      SetLength(Result.Messages, Items.Count);
      for I := 0 to Items.Count - 1 do
      begin
        if not (Items[I] is TJSONObject) then raise Exception.Create('メッセージの形式が不正です。');
        Item := TJSONObject(Items[I]);
        Result.Messages[I].Speaker := Item.GetValue<Integer>('speaker', 0);
        Result.Messages[I].Text := Item.GetValue<string>('text', '');
        Result.Messages[I].TimeText := Item.GetValue<string>('time', '');
        Result.Messages[I].PhotoFile := Item.GetValue<string>('photo', '');
      end;
    end;
    Result.Validate;
  finally
    Value.Free;
  end;
end;

function TMineConversation.ToJSON: string;
var
  Root, Item: TJSONObject;
  Items: TJSONArray;
  Speaker: TMineSpeaker;
  Message: TMineMessage;
begin
  Validate;
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Root.AddPair('title', Title);
    Item := TJSONObject.Create;
    Root.AddPair('colors', Item);
    Item.AddPair('background', TJSONNumber.Create(Integer(BackgroundColor)));
    Item.AddPair('text', TJSONNumber.Create(Integer(TextColor)));
    Item.AddPair('outgoing', TJSONNumber.Create(Integer(OutgoingColor)));
    Item.AddPair('incoming', TJSONNumber.Create(Integer(IncomingColor)));
    Items := TJSONArray.Create;
    Root.AddPair('speakers', Items);
    for Speaker in Speakers do
    begin
      Item := TJSONObject.Create;
      Items.AddElement(Item);
      Item.AddPair('name', Speaker.Name);
      Item.AddPair('icon', Speaker.IconFile);
      Item.AddPair('character', Speaker.CharacterName);
      Item.AddPair('outgoing', TJSONBool.Create(Speaker.Outgoing));
      Item.AddPair('scale', TJSONNumber.Create(Speaker.IconScale));
      Item.AddPair('x', TJSONNumber.Create(Speaker.IconX));
      Item.AddPair('y', TJSONNumber.Create(Speaker.IconY));
      Item.AddPair('background', TJSONNumber.Create(Integer(Speaker.IconBackground)));
    end;
    Items := TJSONArray.Create;
    Root.AddPair('messages', Items);
    for Message in Messages do
    begin
      Item := TJSONObject.Create;
      Items.AddElement(Item);
      Item.AddPair('speaker', TJSONNumber.Create(Message.Speaker));
      Item.AddPair('text', Message.Text);
      Item.AddPair('time', Message.TimeText);
      Item.AddPair('photo', Message.PhotoFile);
    end;
    Result := Root.ToJSON;
    if Length(Result) > 8 * 1024 * 1024 then
      raise Exception.Create('会話データが大きすぎます。メッセージ数を減らしてください。');
  finally
    Root.Free;
  end;
end;

end.
