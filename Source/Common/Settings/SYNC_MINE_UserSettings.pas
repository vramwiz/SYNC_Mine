unit SYNC_MINE_UserSettings;

// Documents\SYNC_MINE に、最近使ったキャラと再利用するアイコン設定を保持する。

interface

uses
  System.Classes, SYNC_MINE_Conversation;

type
  TMineCharacterHistory = class
  private
    FFolder: string;
    FCharacters, FPending: TArray<TMineSpeaker>;
    procedure ReadFile;
    function Serialize: string;
  public
    // Folderの省略時はWindowsのマイドキュメント。明示指定は検証用にも使える。
    constructor Create(const Folder: string = '');
    procedure Load;
    // 履歴を新しい順に置き、続いて重複しない既存キャラ名を追加する。
    procedure FillNames(Names, BuiltinNames: TStrings);
    function Find(const Name: string; out Speaker: TMineSpeaker): Boolean;
    // メモリ内の履歴を更新する。キャンセルではSaveを呼ばず破棄できる。
    procedure Remember(const Speaker: TMineSpeaker);
    // 最新の保存内容へ変更分を合流してから、JSONを一括置換する。
    procedure Save;
    property Folder: string read FFolder;
  end;

// リダイレクト先を含むWindowsのDocuments配下に作成し、絶対パスを返す。
function MineUserDataFolder: string;

implementation

uses
  System.Generics.Collections, System.Hash, System.IOUtils, System.JSON,
  System.SysUtils, Winapi.Windows;

const
  HISTORY_FILE_NAME = 'characters.json';

function MineUserDataFolder: string;
var
  Documents: string;
begin
  Documents := TPath.GetDocumentsPath;
  if Documents = '' then raise Exception.Create('マイドキュメントを取得できませんでした。');
  Result := TPath.Combine(Documents, 'SYNC_MINE');
  if not ForceDirectories(Result) then
    raise Exception.Create('設定フォルダーを作成できませんでした: ' + Result);
end;

constructor TMineCharacterHistory.Create(const Folder: string);
begin
  inherited Create;
  if Folder = '' then FFolder := MineUserDataFolder
  else FFolder := ExpandFileName(Folder);
end;

procedure ValidateProfile(const Speaker: TMineSpeaker);
var
  Data: TMineConversation;
begin
  Data := TMineConversation.NewConversation;
  SetLength(Data.Speakers, 1);
  Data.Speakers[0] := Speaker;
  Data.Validate;
end;

procedure Promote(var Characters: TArray<TMineSpeaker>; const Speaker: TMineSpeaker);
var
  I, J: Integer;
begin
  I := 0;
  while (I < Length(Characters)) and not SameText(Characters[I].Name, Speaker.Name) do Inc(I);
  if I = Length(Characters) then SetLength(Characters, I + 1);
  for J := I downto 1 do Characters[J] := Characters[J - 1];
  Characters[0] := Speaker;
end;

procedure TMineCharacterHistory.Load;
begin
  ReadFile;
  FPending := nil;
end;

procedure TMineCharacterHistory.ReadFile;
var
  FileName, Text: string;
  Value: TJSONValue;
  Root, Item: TJSONObject;
  Items: TJSONArray;
  Characters: TArray<TMineSpeaker>;
  I: Integer;
begin
  FileName := TPath.Combine(FFolder, HISTORY_FILE_NAME);
  if not FileExists(FileName) then
  begin
    FCharacters := nil;
    Exit;
  end;
  Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
  Value := TJSONObject.ParseJSONValue(Text);
  try
    if not (Value is TJSONObject) then
      raise Exception.Create('キャラ履歴のJSONが不正です: ' + FileName);
    Root := TJSONObject(Value);
    if (Root.GetValue<Integer>('version', 0) <> 1) or
      not Root.TryGetValue<TJSONArray>('characters', Items) then
      raise Exception.Create('キャラ履歴の形式に対応していません: ' + FileName);
    Characters := nil;
    // ファイルの先頭が最新。重複があっても先頭の設定を優先する。
    for I := Items.Count - 1 downto 0 do
    begin
      if not (Items[I] is TJSONObject) then
        raise Exception.Create('キャラ履歴の項目が不正です: ' + FileName);
      Item := TJSONObject(Items[I]);
      SetLength(Characters, Length(Characters) + 1);
      Characters[High(Characters)] := Default(TMineSpeaker);
      with Characters[High(Characters)] do
      begin
        Name := Item.GetValue<string>('name', '').Trim;
        IconFile := Item.GetValue<string>('icon', '');
        CharacterName := Item.GetValue<string>('character', '');
        IconScale := Item.GetValue<Double>('scale', 100);
        IconX := Item.GetValue<Double>('x', 0);
        IconY := Item.GetValue<Double>('y', 0);
        IconBackground := Item.GetValue<Integer>('background', MINE_DEFAULT_ICON_BACKGROUND);
      end;
      ValidateProfile(Characters[High(Characters)]);
    end;
    FCharacters := nil;
    for I := 0 to High(Characters) do Promote(FCharacters, Characters[I]);
  finally
    Value.Free;
  end;
end;

procedure TMineCharacterHistory.FillNames(Names, BuiltinNames: TStrings);
var
  Speaker: TMineSpeaker;
  Name: string;
begin
  Names.BeginUpdate;
  try
    Names.Clear;
    for Speaker in FCharacters do Names.Add(Speaker.Name);
    for Name in BuiltinNames do
      if Names.IndexOf(Name) < 0 then Names.Add(Name);
  finally
    Names.EndUpdate;
  end;
end;

function TMineCharacterHistory.Find(const Name: string; out Speaker: TMineSpeaker): Boolean;
var
  Candidate: TMineSpeaker;
begin
  Speaker := Default(TMineSpeaker);
  for Candidate in FCharacters do
    if SameText(Candidate.Name, Name.Trim) then
    begin
      Speaker := Candidate;
      Exit(True);
    end;
  Result := False;
end;

procedure TMineCharacterHistory.Remember(const Speaker: TMineSpeaker);
var
  Profile: TMineSpeaker;
begin
  Profile := Speaker;
  Profile.Name := Profile.Name.Trim;
  // 自分／相手は会話に属するため、共有するキャラ設定へ含めない。
  Profile.Outgoing := False;
  ValidateProfile(Profile);
  Promote(FCharacters, Profile);
  Promote(FPending, Profile);
end;

function TMineCharacterHistory.Serialize: string;
var
  Root, Item: TJSONObject;
  Items: TJSONArray;
  Speaker: TMineSpeaker;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Items := TJSONArray.Create;
    Root.AddPair('characters', Items);
    for Speaker in FCharacters do
    begin
      Item := TJSONObject.Create;
      Items.AddElement(Item);
      Item.AddPair('name', Speaker.Name);
      Item.AddPair('icon', Speaker.IconFile);
      Item.AddPair('character', Speaker.CharacterName);
      Item.AddPair('scale', TJSONNumber.Create(Speaker.IconScale));
      Item.AddPair('x', TJSONNumber.Create(Speaker.IconX));
      Item.AddPair('y', TJSONNumber.Create(Speaker.IconY));
      Item.AddPair('background', TJSONNumber.Create(Integer(Speaker.IconBackground)));
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure TMineCharacterHistory.Save;
var
  Fresh: TMineCharacterHistory;
  Mutex: THandle;
  WaitResult: DWORD;
  TempFile, FileName, MutexName: string;
  I: Integer;
begin
  if Length(FPending) = 0 then Exit;
  ForceDirectories(FFolder);
  MutexName := 'Local\SYNC_MINE.Characters.' +
    Copy(THashSHA2.GetHashString(LowerCase(FFolder)), 1, 24);
  Mutex := CreateMutex(nil, False, PChar(MutexName));
  if Mutex = 0 then RaiseLastOSError;
  try
    WaitResult := WaitForSingleObject(Mutex, 5000);
    if not (WaitResult in [WAIT_OBJECT_0, WAIT_ABANDONED]) then
      raise Exception.Create('キャラ履歴の保存を待機できませんでした。もう一度閉じるを押してください。');
    try
      Fresh := TMineCharacterHistory.Create(FFolder);
      try
        Fresh.Load;
        for I := High(FPending) downto 0 do Fresh.Remember(FPending[I]);
        FileName := TPath.Combine(FFolder, HISTORY_FILE_NAME);
        TempFile := TPath.Combine(FFolder, TPath.GetRandomFileName + '.tmp');
        try
          TFile.WriteAllText(TempFile, Fresh.Serialize, TEncoding.UTF8);
          if not MoveFileEx(PChar(TempFile), PChar(FileName),
            MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
        finally
          if FileExists(TempFile) then TFile.Delete(TempFile);
        end;
        FCharacters := Copy(Fresh.FCharacters);
        FPending := nil;
      finally
        Fresh.Free;
      end;
    finally
      ReleaseMutex(Mutex);
    end;
  finally
    CloseHandle(Mutex);
  end;
end;

end.
