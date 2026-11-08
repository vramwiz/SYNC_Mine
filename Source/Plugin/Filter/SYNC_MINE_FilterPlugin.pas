unit SYNC_MINE_FilterPlugin;

// 標準パラメータ、会話の確定、オブジェクト画像へのスマホ合成を接続する。

interface

uses
  AviUtl2FilterTypes;

function GetMineFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.Math, System.SyncObjs, System.SysUtils, System.Types, System.UITypes,
  Winapi.GDIPAPI, Winapi.GDIPOBJ, Vcl.Dialogs, PluginFilterTable,
  SYNC_MINE_Conversation, SYNC_MINE_Renderer, SYNC_MINE_SettingsForm;

const
  EFFECT_NAME = 'MINE';
  DATA_ITEM_NAME = '会話データ';

type
  TMineVideoSession = class
  private
    FLock: TCriticalSection;
    FRenderer: TMineRenderer;
    FInput: TArray<TPIXEL_RGBA>;
    FJSON: string;
    FOrientation: Integer;
    FPrepared: Boolean;
    function Composite(Image: TGPBitmap; const Bounds: TRect; Width, Opacity: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Render(Video: PFILTER_PROC_VIDEO);
  end;

var
  SettingsButton: TFILTER_ITEM_BUTTON;
  XItem, YItem, ScaleItem, TransparencyItem, StageItem: TFILTER_ITEM_TRACK;
  OrientationItem: TFILTER_ITEM_SELECT;
  OrientationOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  PhoneColorItem: TFILTER_ITEM_COLOR;
  DataItem: TFILTER_ITEM_STRING;
  StorageGroup: TFILTER_ITEM_GROUP;
  PluginTableInitialized: Boolean;

procedure SettingsButtonCallback(Edit: PEDIT_SECTION); cdecl;
const
  Names: array[0..2] of string = ('会話データ', 'スマホの方向', 'スマホの色');
var
  Obj: OBJECT_HANDLE;
  Original, Values: array[0..2] of string;
  JSON, ColorText: string;
  PhoneColor, OriginalPhoneColor: Cardinal;
  Orientation, OriginalOrientation, I, J: Integer;
  Restored: Boolean;

  function ReadItem(const Name: string): string;
  var
    Value: PAnsiChar;
  begin
    Value := Edit^.GetObjectItemValue(Obj, EFFECT_NAME, PWideChar(Name));
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
    Result := Edit^.SetObjectItemValue(Obj, EFFECT_NAME, PWideChar(Names[Index]), PAnsiChar(Encoded));
    if Result then Result := SameValue(Index, ReadItem(Names[Index]), Value);
  end;

begin
  try
    if (Edit = nil) or not Assigned(Edit^.GetFocusObject) or
      not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then
      raise Exception.Create('AviUtl2の編集APIを取得できませんでした。');
    Obj := Edit^.GetFocusObject;
    if Obj = nil then raise Exception.Create('MINEを配置したオブジェクトを選択してください。');
    if Assigned(Edit^.CountObjectEffect) and (Edit^.CountObjectEffect(Obj, EFFECT_NAME) <> 1) then
      raise Exception.Create('設定対象にはMINEを1つ配置してください。');
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
constructor TMineVideoSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FRenderer := TMineRenderer.Create;
end;

destructor TMineVideoSession.Destroy;
begin
  FRenderer.Free;
  FLock.Free;
  inherited;
end;

function TMineVideoSession.Composite(Image: TGPBitmap; const Bounds: TRect;
  Width, Opacity: Integer): Boolean;
var
  Data: TBitmapData;
  Source: PByte;
  Target: PPIXEL_RGBA;
  X, Y, Alpha, Inverse: Integer;
begin
  Result := False;
  if Image.LockBits(MakeRect(0, 0, Bounds.Width, Bounds.Height), ImageLockModeRead,
    PixelFormat32bppPARGB, Data) <> Ok then Exit;
  try
    for Y := Bounds.Top to Bounds.Bottom - 1 do
    begin
      Source := PByte(NativeInt(Data.Scan0) + NativeInt(Y - Bounds.Top) * Data.Stride);
      Target := @FInput[Y * Width + Bounds.Left];
      for X := Bounds.Left to Bounds.Right - 1 do
      begin
        Alpha := (Source[3] * Opacity + 127) div 255;
        if Alpha > 0 then
        begin
          Result := True;
          Inverse := 255 - Alpha;
          Target^.R := Min(255, (Source[2] * Opacity + Target^.R * Inverse + 127) div 255);
          Target^.G := Min(255, (Source[1] * Opacity + Target^.G * Inverse + 127) div 255);
          Target^.B := Min(255, (Source[0] * Opacity + Target^.B * Inverse + 127) div 255);
          Target^.A := Min(255, Alpha + (Target^.A * Inverse + 127) div 255);
        end;
        Inc(Source, 4);
        Inc(Target);
      end;
    end;
  finally
    Image.UnlockBits(Data);
  end;
end;

procedure TMineVideoSession.Render(Video: PFILTER_PROC_VIDEO);
var
  Width, Height, Orientation, Opacity: Integer;
  JSON: string;
  Bounds, Clipped: TRect;
  Image: TGPBitmap;
  PhoneColor: ARGB;
begin
  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  if (Width <= 0) or (Height <= 0) or (Width > 8192) or (Height > 8192) or
    (Int64(Width) * Height > 33554432) or not Assigned(Video^.GetImageData) or
    not Assigned(Video^.SetImageData) then Exit;
  Opacity := Round(255 * (100 - EnsureRange(TransparencyItem.Value, 0.0, 100.0)) / 100);
  if (Opacity <= 0) or (ScaleItem.Value <= 0) then Exit;
  Orientation := Ord(OrientationItem.Value = 1);
  Bounds := MinePhoneBounds(Width, Height, Orientation, XItem.Value, YItem.Value, ScaleItem.Value / 100);
  if not System.Types.IntersectRect(Clipped, Bounds, Rect(0, 0, Width, Height)) then Exit;
  JSON := string(DataItem.Value);
  if not FPrepared or (JSON <> FJSON) or (Orientation <> FOrientation) then
  begin
    FRenderer.Prepare(TMineConversation.FromJSON(JSON), Orientation);
    FJSON := JSON;
    FOrientation := Orientation;
    FPrepared := True;
  end;
  PhoneColor := $FF000000 or (Cardinal(PhoneColorItem.R) shl 16) or
    (Cardinal(PhoneColorItem.G) shl 8) or PhoneColorItem.B;
  Image := FRenderer.RenderSurface(Bounds, Clipped,
    EnsureRange(StageItem.Value, 0.0, MINE_MAX_MESSAGES * 100.0), PhoneColor);
  if Image = nil then Exit;
  // 合成する現在のオブジェクト画像のみを読む。ホスト画面の取得や保存は行わない。
  SetLength(FInput, NativeInt(Width) * Height);
  Video^.GetImageData(@FInput[0]);
  if Composite(Image, Clipped, Width, Opacity) then
    Video^.SetImageData(@FInput[0], Width, Height);
end;

function MineProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Session: TMineVideoSession;
begin
  Result := 1;
  try
    if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
    Session := TMineVideoSession(Video^.UserData);
    Session.FLock.Acquire;
    try
      Session.Render(Video);
    finally
      Session.FLock.Release;
    end;
  except
    // 不正な会話や画像で描けないフレームは元の映像を維持する。
  end;
end;

function MineCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TMineVideoSession.Create;
  except
  end;
end;

procedure MineDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TMineVideoSession(UserData).Free;
  except
  end;
end;

function GetMineFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA,
      EFFECT_NAME, 'SYNC', 'スマホ本体とメッセージの会話を描画', MineProcVideo, nil);
    AddButton(SettingsButton, '設定', SettingsButtonCallback);
    OrientationOptions[0].Name := '縦向き';
    OrientationOptions[0].Value := 0;
    OrientationOptions[1].Name := '横向き';
    OrientationOptions[1].Value := 1;
    AddSelect(OrientationItem, 'スマホの方向', 0, @OrientationOptions[0]);
    AddColor(PhoneColorItem, 'スマホの色', $28, $24, $20);
    AddTrack(StageItem, '段階', 0, 0, MINE_MAX_MESSAGES * 100, 1);
    AddTrack(XItem, 'X', 0, -4096, 4096, 0.1);
    AddTrack(YItem, 'Y', 0, -4096, 4096, 0.1);
    AddTrack(ScaleItem, '拡大率', 100, 0, 1000, 0.1);
    AddTrack(TransparencyItem, '透明度', 0, 0, 100, 1);
    AddGroup(StorageGroup, '内部データ', 0);
    AddString(DataItem, DATA_ITEM_NAME, '{}');
    GetPluginTable^.Func_Create := MineCreate;
    GetPluginTable^.Func_Destroy := MineDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
