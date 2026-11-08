unit SYNC_MINE_CharacterIcons;

// 既存のキャラリソースと VectorRenderer を使い、参照用PNGを生成する。

interface

uses
  System.Classes;

// 埋め込み済みキャラ名を表示順に列挙する。共有リソース自体は書き換えない。
procedure MineCharacterNames(Names: TStrings);
// 既存のベクター描画器でPNGを生成し、ユーザーキャッシュの絶対パスを返す。
function MineCharacterIconFile(const Name: string): string;

implementation

uses
  System.IOUtils, System.SyncObjs, System.SysUtils, Winapi.Windows,
  Vcl.Graphics, Vcl.Imaging.pngimage, VectorRenderer, VectorRendererImageList,
  SYNC_MINE_UserSettings;

var
  Catalog: TVectorRendererImageList;
  CatalogLock: TCriticalSection;

type
  PMinePixelRow = ^TMinePixelRow;
  TMinePixelRow = array[0..MaxInt div SizeOf(TRGBQuad) - 1] of TRGBQuad;

procedure EnsureCatalog;
var
  Stream: TResourceStream;
  Lines: TStringList;
begin
  if Catalog <> nil then Exit;
  Lines := TStringList.Create;
  try
    Stream := TResourceStream.Create(HInstance, 'SERIF_CHARA_VECTOR_DATA', RT_RCDATA);
    try
      Lines.LoadFromStream(Stream, TEncoding.UTF8);
    finally
      Stream.Free;
    end;
    Catalog := TVectorRendererImageList.Create;
    try
      Catalog.LoadFromStrings(Lines, '[', ']');
    except
      FreeAndNil(Catalog);
      raise;
    end;
  finally
    Lines.Free;
  end;
end;

procedure MineCharacterNames(Names: TStrings);
var
  I: Integer;
begin
  CatalogLock.Acquire;
  try
    EnsureCatalog;
    Names.BeginUpdate;
    try
      Names.Clear;
      for I := 0 to Catalog.Count - 1 do
        Names.Add(ChangeFileExt(ExtractFileName(Catalog.Images[I].FileName), ''));
    finally
      Names.EndUpdate;
    end;
  finally
    CatalogLock.Release;
  end;
end;

function MineCharacterIconFile(const Name: string): string;
var
  Item: TVectorRendererImageItem;
  Folder, TempFile: string;
  Bitmap: TBitmap;
  PNG: TPngImage;
  Stream: TResourceStream;
  Signature: TStringList;
  X, Y: Integer;
  Row: PMinePixelRow;
  Alpha: PByteArray;
begin
  Result := '';
  CatalogLock.Acquire;
  try
    EnsureCatalog;
    Item := Catalog.FindByFileName(Name + '.ini');
    if Item = nil then raise Exception.Create('キャラアイコンが見つかりません: ' + Name);
    Signature := TStringList.Create;
    try
      Stream := TResourceStream.Create(HInstance, 'SERIF_CHARA_VECTOR_SIGNATURE', RT_RCDATA);
      try
        Signature.LoadFromStream(Stream, TEncoding.ASCII);
      finally
        Stream.Free;
      end;
      Folder := TPath.Combine(MineUserDataFolder,
        'Icons\' + Copy(Signature.Text.Trim, 1, 16) + '\alpha');
    finally
      Signature.Free;
    end;
    ForceDirectories(Folder);
    Result := TPath.Combine(Folder, ExtractFileName(Name) + '.png');
    if FileExists(Result) then Exit;
    Bitmap := TVectorRenderer.RenderToBitmap(Item.Data, 512, 512, vrbTransparent);
    try
      PNG := TPngImage.Create;
      try
        PNG.Assign(Bitmap);
        // TPngImage.Assignだけでは32bit Bitmapのアルファが失われるため明示的に渡す。
        PNG.CreateAlpha;
        for Y := 0 to Bitmap.Height - 1 do
        begin
          Row := Bitmap.ScanLine[Y];
          Alpha := PNG.AlphaScanline[Y];
          for X := 0 to Bitmap.Width - 1 do Alpha[X] := Row[X].rgbReserved;
        end;
        TempFile := Result + '.' + IntToHex(GetCurrentProcessId, 8) + '.tmp';
        try
          PNG.SaveToFile(TempFile);
          if not MoveFileEx(PChar(TempFile), PChar(Result), MOVEFILE_REPLACE_EXISTING) then
            RaiseLastOSError;
        finally
          if FileExists(TempFile) then TFile.Delete(TempFile);
        end;
      finally
        PNG.Free;
      end;
    finally
      Bitmap.Free;
    end;
  finally
    CatalogLock.Release;
  end;
end;

initialization
  CatalogLock := TCriticalSection.Create;
finalization
  Catalog.Free;
  CatalogLock.Free;
end.
