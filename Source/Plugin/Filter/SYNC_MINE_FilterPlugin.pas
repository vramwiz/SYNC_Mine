unit SYNC_MINE_FilterPlugin;

// メディアオブジェクトにスマホの透過映像と会話の生成音を渡す。

interface

uses
  AviUtl2FilterTypes;

const MINE_REQUIRED_VERSION = 2011600;

function GetMineFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.Math, System.SyncObjs, System.SysUtils, System.UITypes,
  Winapi.GDIPAPI, Winapi.GDIPOBJ, Vcl.Dialogs, PluginFilterTable,
  SYNC_MINE_Conversation, SYNC_MINE_Renderer, SYNC_MINE_Audio, SYNC_MINE_SettingsForm;

const
  EFFECT_NAME = 'MINE';
  DATA_ITEM_NAME = '会話データ';

type
  TMineSession = class
  private
    FVideoLock, FAudioLock: TCriticalSection;
    FRenderer: TMineRenderer;
    FAudio: TMineAudio;
    FPixels: TArray<TPIXEL_RGBA>;
    FSamples: TArray<Single>;
    FVideoJSON, FAudioJSON: string;
    FOrientation: Integer;
    FVideoPrepared, FAudioPrepared: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function RenderVideo(Video: PFILTER_PROC_VIDEO): Byte;
    function RenderAudio(Audio: PFILTER_PROC_AUDIO): Byte;
  end;

var
  SettingsButton: TFILTER_ITEM_BUTTON;
  VolumeItem: TFILTER_ITEM_TRACK;
  OrientationItem: TFILTER_ITEM_SELECT;
  OrientationOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  PhoneColorItem: TFILTER_ITEM_COLOR;
  DataItem: TFILTER_ITEM_STRING;
  StorageGroup: TFILTER_ITEM_GROUP;
  PluginTableInitialized: Boolean;

procedure SettingsButtonCallback(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: PWideChar); cdecl;
const
  Names: array[0..2] of string = ('会話データ', 'スマホの方向', 'スマホの色');
var
  Original, Values: array[0..2] of string;
  JSON, ColorText: string;
  PhoneColor, OriginalPhoneColor: Cardinal;
  Orientation, OriginalOrientation, I, J: Integer;
  Restored: Boolean;

  function ReadItem(const Name: string): string;
  var
    Value: PAnsiChar;
  begin
    Value := Edit^.GetObjectItemValue(Obj, Effect, PWideChar(Name));
    if Value = nil then raise Exception.CreateFmt('「%s」を取得できませんでした。', [Name]);
    Result := string(UTF8String(Value));
  end;

  function DirectionValue(const Text: string): Integer;
  begin
    if (Text = '横向き') or (Text = '1') then Result := 1
    else if (Text = '縦向き') or (Text = '0') then Result := 0
    else Result := -1;
  end;

  function ColorValue(const Text: string): Cardinal;
  var
    Value: string;
  begin
    Value := Text.Trim;
    if Value.StartsWith('#') or Value.StartsWith('$') then Delete(Value, 1, 1);
    if Value.StartsWith('0x', True) then Delete(Value, 1, 2);
    Result := Cardinal(StrToInt64Def('$' + Value, $202428)) and $FFFFFF;
  end;

  function SameValue(Index: Integer; const A, B: string): Boolean;
  begin
    if A = B then Exit(True);
    case Index of
      1: Result := (DirectionValue(A) >= 0) and (DirectionValue(A) = DirectionValue(B));
      2: Result := ColorValue(A) = ColorValue(B);
    else
      Result := False;
    end;
  end;

  function WriteItem(Index: Integer; const Value: string): Boolean;
  var
    Encoded: UTF8String;
  begin
    Encoded := UTF8String(Value);
    Result := Edit^.SetObjectItemValue(Obj, Effect, PWideChar(Names[Index]), PAnsiChar(Encoded));
    if Result then Result := SameValue(Index, ReadItem(Names[Index]), Value);
  end;

begin
  try
    if (Edit = nil) or (Obj = nil) or (Effect = nil) or
      not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then
      raise Exception.Create('AviUtl2の編集APIを取得できませんでした。');
    for I := 0 to High(Names) do Original[I] := ReadItem(Names[I]);
    JSON := Original[0];
    Orientation := Max(0, DirectionValue(Original[1]));
    ColorText := Original[2];
    PhoneColor := ColorValue(ColorText) or $FF000000;
    OriginalPhoneColor := PhoneColor;
    OriginalOrientation := Orientation;
    if not EditMineSettings(JSON, Orientation, PhoneColor) then Exit;
    Values := Original;
    Values[0] := JSON;
    if Orientation <> OriginalOrientation then
      if Orientation = 1 then Values[1] := '横向き' else Values[1] := '縦向き';
    if PhoneColor <> OriginalPhoneColor then Values[2] := IntToHex(PhoneColor and $FFFFFF, 6);
    // 会話と基本設定を同じ編集コールバック内で確定し、失敗時は元の値へ戻す。
    for I := 0 to High(Names) do
      if not SameValue(I, Original[I], Values[I]) then
      try
        if not WriteItem(I, Values[I]) then
          raise Exception.CreateFmt('「%s」を完全に保存できませんでした。', [Names[I]]);
      except
        Restored := True;
        for J := I downto 0 do
          if not SameValue(J, Original[J], Values[J]) then
            try
              if not WriteItem(J, Original[J]) then Restored := False;
            except
              Restored := False;
            end;
        if not Restored then raise Exception.Create('設定の保存に失敗し、一部を元に戻せませんでした。');
        raise;
      end;
  except
    on E: Exception do
      try
        MessageDlg(E.Message, mtError, [mbOK], 0);
      except
        // Delphi 例外を AviUtl2 のコールバックへ漏らさない。
      end;
  end;
end;
constructor TMineSession.Create;
begin
  inherited;
  FVideoLock := TCriticalSection.Create;
  FAudioLock := TCriticalSection.Create;
  FRenderer := TMineRenderer.Create;
  FAudio := TMineAudio.Create;
end;

destructor TMineSession.Destroy;
begin
  FAudio.Free;
  FRenderer.Free;
  FAudioLock.Free;
  FVideoLock.Free;
  inherited;
end;

function TMineSession.RenderVideo(Video: PFILTER_PROC_VIDEO): Byte;
var
  BitmapData: TBitmapData;
  Source: PByte;
  Target: PPIXEL_RGBA;
  X, Y, Width, Height, Orientation: Integer;
  JSON: string;
  Image: TGPBitmap;
  PhoneColor: ARGB;
begin
  Result := 0;
  if not Assigned(Video^.SetImageData) then Exit;
  FVideoLock.Acquire;
  try
    JSON := string(DataItem.Value);
    Orientation := Ord(OrientationItem.Value = 1);
    if not FVideoPrepared or (JSON <> FVideoJSON) or (Orientation <> FOrientation) then
    begin
      FVideoPrepared := False;
      FRenderer.Prepare(TMineConversation.FromJSON(JSON), Orientation);
      FVideoJSON := JSON;
      FOrientation := Orientation;
      FVideoPrepared := True;
    end;
    PhoneColor := $FF000000 or (Cardinal(PhoneColorItem.R) shl 16) or
      (Cardinal(PhoneColorItem.G) shl 8) or PhoneColorItem.B;
    Image := FRenderer.RenderSurface(Video^.Object_^.Time * 1000, PhoneColor);
    Width := Image.GetWidth;
    Height := Image.GetHeight;
    SetLength(FPixels, Width * Height);
    // GDI+ の straight BGRA を SDK の straight RGBA に並べ替える。
    if Image.LockBits(MakeRect(0, 0, Width, Height), ImageLockModeRead,
      PixelFormat32bppARGB, BitmapData) <> Ok then Exit;
    try
      for Y := 0 to Height - 1 do
      begin
        Source := PByte(NativeInt(BitmapData.Scan0) + NativeInt(Y) * BitmapData.Stride);
        Target := @FPixels[Y * Width];
        for X := 0 to Width - 1 do
        begin
          Target^.R := Source[2];
          Target^.G := Source[1];
          Target^.B := Source[0];
          Target^.A := Source[3];
          Inc(Source, 4);
          Inc(Target);
        end;
      end;
    finally
      Image.UnlockBits(BitmapData);
    end;
    Video^.SetImageData(@FPixels[0], Width, Height);
    Result := 1;
  finally
    FVideoLock.Release;
  end;
end;

function TMineSession.RenderAudio(Audio: PFILTER_PROC_AUDIO): Byte;
var
  Count, Channel, SampleRate: Integer;
  JSON: string;
begin
  Result := 0;
  if (Audio^.Scene = nil) or not Assigned(Audio^.SetSampleData) then Exit;
  Count := Audio^.Object_^.SampleNum;
  SampleRate := Audio^.Scene^.SampleRate;
  if (Count < 0) or (Count > 16777216) or (SampleRate < 8000) or (SampleRate > 384000) or
    (Audio^.Object_^.ChannelNum < 1) or (Audio^.Object_^.ChannelNum > 32) then Exit;
  if Count = 0 then Exit(1);
  FAudioLock.Acquire;
  try
    JSON := string(DataItem.Value);
    if not FAudioPrepared or (JSON <> FAudioJSON) then
    begin
      FAudio.Prepare(TMineConversation.FromJSON(JSON));
      FAudioJSON := JSON;
      FAudioPrepared := True;
    end;
    if not FAudio.Render(Audio^.Object_^.SampleIndex, Count, SampleRate, VolumeItem.Value, FSamples) then
    begin
      SetLength(FSamples, Count);
      FillChar(FSamples[0], Count * SizeOf(Single), 0);
    end;
    for Channel := 0 to Audio^.Object_^.ChannelNum - 1 do
      Audio^.SetSampleData(@FSamples[0], Channel);
    Result := 1;
  finally
    FAudioLock.Release;
  end;
end;

function MineProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 0;
  try
    if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
    Result := TMineSession(Video^.UserData).RenderVideo(Video);
  except
  end;
end;

function MineProcAudio(Audio: PFILTER_PROC_AUDIO): Byte; cdecl;
begin
  Result := 0;
  try
    if (Audio = nil) or (Audio^.Object_ = nil) or (Audio^.UserData = nil) then Exit;
    Result := TMineSession(Audio^.UserData).RenderAudio(Audio);
  except
  end;
end;

function MineCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TMineSession.Create;
  except
  end;
end;

procedure MineDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TMineSession(UserData).Free;
  except
  end;
end;

function GetMineFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_AUDIO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      EFFECT_NAME, 'SYNC', 'スマホの会話演出と効果音', MineProcVideo, MineProcAudio);
    AddButton(SettingsButton, '設定', nil);
    SettingsButton.Callback2 := SettingsButtonCallback;
    OrientationOptions[0].Name := '縦向き';
    OrientationOptions[0].Value := 0;
    OrientationOptions[1].Name := '横向き';
    OrientationOptions[1].Value := 1;
    AddSelect(OrientationItem, 'スマホの方向', 0, @OrientationOptions[0]);
    AddColor(PhoneColorItem, 'スマホの色', $28, $24, $20);
    AddTrack(VolumeItem, '効果音の音量', MINE_DEFAULT_VOLUME, 0, 100, 1);
    AddGroup(StorageGroup, '内部データ', 0);
    AddString(DataItem, DATA_ITEM_NAME, '{}');
    GetPluginTable^.Func_Create := MineCreate;
    GetPluginTable^.Func_Destroy := MineDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
