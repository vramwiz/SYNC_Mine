unit SYNC_MINE_Renderer;

// スマホ・会話・画像を透明面へ描く。時刻から表示とスクロールを計算する。

interface

uses
  System.Generics.Collections, System.Types, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  SYNC_MINE_Conversation;

type
  TMineRenderer = class
  private type
    TRow = record
      Top, Height, Width, BubbleHeight, PhotoHeight: Single;
    end;
  private
    FData: TMineConversation;
    FRows: TArray<TRow>;
    FPictures: TObjectDictionary<string, TGPBitmap>;
    FBodyFont, FSmallFont, FHeaderFont: TGPFont;
    FWidth, FHeight: Integer;
    FSurface: TGPBitmap;
    function Picture(const FileName: string): TGPBitmap;
    procedure DrawRow(Target: TGPGraphics; Index: Integer; Y, Phase: Single; IsRead: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    // データ変更時と方向変更時だけ文字を測り、画像参照キャッシュを更新する。
    procedure Prepare(const Data: TMineConversation; Orientation: Integer);
    procedure Draw(Target: TGPGraphics; const Destination: TRect; TimeMS: Double;
      PhoneColor: ARGB);
    // 返す画像は描画器が所有し、次の呼出しまで有効。
    function RenderSurface(TimeMS: Double; PhoneColor: ARGB): TGPBitmap;
  end;

function StartMineGraphics: Boolean;
procedure StopMineGraphics;
procedure MinePhoneSize(Orientation: Integer; out Width, Height: Integer);
// ファイルを開いたままにせず縮小複製する。失敗時はnilを返す。
function LoadMinePicture(const FileName: string): TGPBitmap;
// アイコン枠を画像で埋め、倍率と枠に対する百分率の位置補正を適用する。
procedure DrawMineIcon(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF;
  Scale, X, Y: Double; Opacity: Byte = 255;
  Background: Cardinal = MINE_DEFAULT_ICON_BACKGROUND);

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, SYNC_MINE_CharacterIcons, SYNC_MINE_Timeline;

var
  GraphicsToken: ULONG_PTR;

function StartMineGraphics: Boolean;
var
  Input: TGdiplusStartupInput;
begin
  if GraphicsToken <> 0 then Exit(True);
  Input := Default(TGdiplusStartupInput);
  Input.GdiplusVersion := 1;
  Result := GdiplusStartup(GraphicsToken, @Input, nil) = Ok;
end;

procedure StopMineGraphics;
begin
  if GraphicsToken = 0 then Exit;
  GdiplusShutdown(GraphicsToken);
  GraphicsToken := 0;
end;

procedure MinePhoneSize(Orientation: Integer; out Width, Height: Integer);
begin
  if Orientation = 1 then
  begin
    Width := 820;
    Height := 420;
  end
  else
  begin
    Width := 420;
    Height := 820;
  end;
end;

function LoadMinePicture(const FileName: string): TGPBitmap;
var
  Source: TGPBitmap;
  Target: TGPGraphics;
  Ratio: Double;
  W, H: Integer;
begin
  Result := nil;
  if (FileName = '') or not FileExists(FileName) then Exit;
  Source := TGPBitmap.Create(FileName);
  try
    if Source.GetLastStatus <> Ok then Exit;
    W := Source.GetWidth;
    H := Source.GetHeight;
    if (W < 1) or (H < 1) or (Int64(W) * H > 33554432) then Exit;
    Ratio := Min(1.0, 640.0 / Max(W, H));
    Result := TGPBitmap.Create(Max(1, Round(W * Ratio)), Max(1, Round(H * Ratio)),
      PixelFormat32bppPARGB);
    Target := TGPGraphics.Create(Result);
    try
      Target.Clear(0);
      Target.SetInterpolationMode(InterpolationModeHighQualityBicubic);
      Target.DrawImage(Source, 0, 0, Integer(Result.GetWidth), Integer(Result.GetHeight));
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;
end;

function RoundPath(X, Y, W, H, Radius: Single): TGPGraphicsPath;
begin
  Result := TGPGraphicsPath.Create;
  Radius := Min(Radius, Min(W, H) / 2) * 2;
  Result.AddArc(X, Y, Radius, Radius, 180, 90);
  Result.AddArc(X + W - Radius, Y, Radius, Radius, 270, 90);
  Result.AddArc(X + W - Radius, Y + H - Radius, Radius, Radius, 0, 90);
  Result.AddArc(X, Y + H - Radius, Radius, Radius, 90, 90);
  Result.CloseFigure;
end;

procedure FillRound(Target: TGPGraphics; X, Y, W, H, Radius: Single; Color: ARGB);
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
begin
  Path := RoundPath(X, Y, W, H, Radius);
  Brush := TGPSolidBrush.Create(Color);
  try
    Target.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

procedure TextAt(Target: TGPGraphics; const Text: string; Font: TGPFont;
  X, Y, W, H: Single; Color: ARGB; AlignRight: Boolean = False);
var
  Brush: TGPSolidBrush;
  Format: TGPStringFormat;
begin
  if Text = '' then Exit;
  Brush := TGPSolidBrush.Create(Color);
  Format := TGPStringFormat.Create;
  try
    Format.SetTrimming(StringTrimmingEllipsisCharacter);
    if AlignRight then Format.SetAlignment(StringAlignmentFar);
    Target.DrawString(Text, Length(Text), Font, MakeRect(X, Y, W, H), Format, Brush);
  finally
    Format.Free;
    Brush.Free;
  end;
end;

// sRGBを線形輝度に戻し、背景とのコントラスト比が大きい黒または白を選ぶ。
function ContrastText(Background: Cardinal): Cardinal;
  function Linear(Value: Byte): Double;
  var
    C: Double;
  begin
    C := Value / 255;
    if C <= 0.04045 then Result := C / 12.92
    else Result := Power((C + 0.055) / 1.055, 2.4);
  end;
var
  Luminance: Double;
begin
  Luminance := 0.2126 * Linear((Background shr 16) and $FF) +
    0.7152 * Linear((Background shr 8) and $FF) + 0.0722 * Linear(Background and $FF);
  if Luminance >= 0.1791287847 then Result := $000000 else Result := $FFFFFF;
end;

procedure DrawPicture(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF;
  Opacity: Byte);
var
  Attributes: TGPImageAttributes;
  Matrix: TColorMatrix;
  I: Integer;
begin
  if Image = nil then Exit;
  Attributes := TGPImageAttributes.Create;
  try
    Matrix := Default(TColorMatrix);
    for I := 0 to 4 do Matrix[I, I] := 1;
    Matrix[3, 3] := Opacity / 255;
    Attributes.SetColorMatrix(Matrix);
    Target.DrawImage(Image, Bounds, 0, 0, Image.GetWidth, Image.GetHeight, UnitPixel, Attributes);
  finally
    Attributes.Free;
  end;
end;

procedure DrawMineIcon(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF;
  Scale, X, Y: Double; Opacity: Byte; Background: Cardinal);
var
  Path: TGPGraphicsPath;
  State: GraphicsState;
  Ratio, W, H: Double;
begin
  FillRound(Target, Bounds.X, Bounds.Y, Bounds.Width, Bounds.Height, Bounds.Width / 2,
    (Cardinal(Opacity) shl 24) or (Background and $FFFFFF));
  if Image = nil then Exit;
  Path := TGPGraphicsPath.Create;
  State := Target.Save;
  try
    Path.AddEllipse(Bounds);
    Target.SetClip(Path, CombineModeIntersect);
    Ratio := Max(Bounds.Width / Image.GetWidth, Bounds.Height / Image.GetHeight) * Scale / 100;
    W := Image.GetWidth * Ratio;
    H := Image.GetHeight * Ratio;
    DrawPicture(Target, Image, MakeRect(Single(Bounds.X + (Bounds.Width - W) / 2 + X * Bounds.Width / 100),
      Single(Bounds.Y + (Bounds.Height - H) / 2 + Y * Bounds.Height / 100), Single(W), Single(H)), Opacity);
  finally
    Target.Restore(State);
    Path.Free;
  end;
end;

constructor TMineRenderer.Create;
begin
  inherited;
  FPictures := TObjectDictionary<string, TGPBitmap>.Create([doOwnsValues]);
  FBodyFont := TGPFont.Create('Yu Gothic UI', 20, FontStyleRegular, UnitPixel);
  FSmallFont := TGPFont.Create('Yu Gothic UI', 12, FontStyleRegular, UnitPixel);
  FHeaderFont := TGPFont.Create('Yu Gothic UI', 22, FontStyleBold, UnitPixel);
end;

destructor TMineRenderer.Destroy;
begin
  FSurface.Free;
  FHeaderFont.Free;
  FSmallFont.Free;
  FBodyFont.Free;
  FPictures.Free;
  inherited;
end;

function TMineRenderer.Picture(const FileName: string): TGPBitmap;
begin
  if FileName = '' then Exit(nil);
  if FPictures.TryGetValue(FileName, Result) then Exit;
  if FPictures.Count >= 32 then FPictures.Clear;
  Result := LoadMinePicture(FileName);
  FPictures.Add(FileName, Result);
end;

procedure TMineRenderer.Prepare(const Data: TMineConversation; Orientation: Integer);
var
  Surface: TGPBitmap;
  Target: TGPGraphics;
  TextBounds: TGPRectF;
  Format: TGPStringFormat;
  I: Integer;
  MaxWidth, Top, TextHeight: Single;
  Image: TGPBitmap;
begin
  Data.Validate;
  FData := OrderedMineConversation(Data);
  // 配列はフォームが更新するため、アイコンの補完パスは描画器側の複製へ書く。
  FData.Speakers := Copy(Data.Speakers);
  FPictures.Clear;
  MinePhoneSize(Orientation, FWidth, FHeight);
  for I := 0 to High(FData.Speakers) do
    if FData.Speakers[I].CharacterName <> '' then
      FData.Speakers[I].IconFile := MineCharacterIconFile(FData.Speakers[I].CharacterName);
  SetLength(FRows, Length(FData.Messages));
  Surface := TGPBitmap.Create(1, 1);
  Target := TGPGraphics.Create(Surface);
  Format := TGPStringFormat.Create;
  try
    MaxWidth := Min(420, FWidth - 168);
    Top := 10;
    for I := 0 to High(FRows) do
    begin
      FRows[I] := Default(TRow);
      TextHeight := 0;
      FRows[I].Width := 54;
      if FData.Messages[I].Text <> '' then
      begin
        Target.MeasureString(FData.Messages[I].Text, Length(FData.Messages[I].Text), FBodyFont,
          MakeRect(Single(0), Single(0), MaxWidth - 24, Single(200000)), Format, TextBounds);
        FRows[I].Width := Min(MaxWidth, Max(54, Ceil(TextBounds.Width) + 24));
        TextHeight := Ceil(TextBounds.Height);
      end;
      if FData.Messages[I].PhotoFile <> '' then
      begin
        Image := Picture(FData.Messages[I].PhotoFile);
        FRows[I].Width := MaxWidth;
        if Image <> nil then FRows[I].PhotoHeight := Min(260, (MaxWidth - 12) * Image.GetHeight / Image.GetWidth)
        else FRows[I].PhotoHeight := 100;
        FRows[I].PhotoHeight := Max(48, FRows[I].PhotoHeight);
      end;
      FRows[I].BubbleHeight := Max(42, TextHeight + 18 + FRows[I].PhotoHeight);
      FRows[I].Top := Top;
      FRows[I].Height := FRows[I].BubbleHeight + 32;
      if not FData.Speakers[FData.Messages[I].Speaker].Outgoing then
        FRows[I].Height := FRows[I].Height + 20;
      Top := Top + FRows[I].Height;
    end;
  finally
    Format.Free;
    Target.Free;
    Surface.Free;
  end;
end;

procedure TMineRenderer.DrawRow(Target: TGPGraphics; Index: Integer; Y, Phase: Single; IsRead: Boolean);
var
  Speaker: TMineSpeaker;
  Message: TMineMessage;
  Row: TRow;
  X, BubbleY, TextY, PhotoWidth, PhotoHeight, Ratio, MetaWidth, MetaX: Single;
  Alpha: Cardinal;
  Color, BodyColor: ARGB;
  Metadata: string;
  Photo: TGPBitmap;
  Path: TGPGraphicsPath;
  State, RowState: GraphicsState;
  PopScale, AnchorX, LeftInset: Single;
begin
  Row := FRows[Index];
  Message := FData.Messages[Index];
  Speaker := FData.Speakers[Message.Speaker];
  Alpha := Cardinal(Round(255 * Phase)) shl 24;
  Y := Y + (1 - Phase) * 14;
  RowState := Target.Save;
  try
  PopScale := 0.94 + 0.06 * Phase;
  LeftInset := 0;
  if FWidth > FHeight then LeftInset := 32;
  if Speaker.Outgoing then AnchorX := FWidth - 28 else AnchorX := 24 + LeftInset;
  Target.TranslateTransform(AnchorX, Y);
  Target.ScaleTransform(PopScale, PopScale);
  Target.TranslateTransform(-AnchorX, -Y);
  BubbleY := Y;
  if Speaker.Outgoing then
  begin
    X := FWidth - 28 - Row.Width;
    Color := Alpha or FData.OutgoingColor;
  end
  else
  begin
    X := 70 + LeftInset;
    Color := Alpha or FData.IncomingColor;
    DrawMineIcon(Target, Picture(Speaker.IconFile), MakeRect(24 + LeftInset, Y, Single(36), Single(36)),
      Speaker.IconScale, Speaker.IconX, Speaker.IconY, Alpha shr 24, Speaker.IconBackground);
    TextAt(Target, Speaker.Name, FSmallFont, X, Y - 1, Row.Width, 19, Alpha or FData.TextColor);
    BubbleY := Y + 20;
  end;
  FillRound(Target, X, BubbleY, Row.Width, Row.BubbleHeight, 14, Color);
  BodyColor := Alpha or ContrastText(Color and $FFFFFF);
  TextY := BubbleY + 8;
  if Message.PhotoFile <> '' then
  begin
    Photo := Picture(Message.PhotoFile);
    if Photo <> nil then
    begin
      Path := RoundPath(X + 6, BubbleY + 6, Row.Width - 12, Row.PhotoHeight, 9);
      State := Target.Save;
      try
        Target.SetClip(Path, CombineModeIntersect);
        // 極端に横長・縦長の写真も、枠の縦横比に引き伸ばさない。
        Ratio := Min((Row.Width - 12) / Photo.GetWidth, Row.PhotoHeight / Photo.GetHeight);
        PhotoWidth := Photo.GetWidth * Ratio;
        PhotoHeight := Photo.GetHeight * Ratio;
        DrawPicture(Target, Photo, MakeRect(X + (Row.Width - PhotoWidth) / 2,
          BubbleY + 6 + (Row.PhotoHeight - PhotoHeight) / 2, PhotoWidth, PhotoHeight), Alpha shr 24);
      finally
        Target.Restore(State);
        Path.Free;
      end;
    end
    else TextAt(Target, '画像を読み込めません', FSmallFont, X + 12, TextY + 22,
      Row.Width - 24, 44, BodyColor);
    TextY := BubbleY + Row.PhotoHeight + 10;
  end;
  TextAt(Target, Message.Text, FBodyFont, X + 12, TextY, Row.Width - 24,
    Row.BubbleHeight - (TextY - BubbleY) - 4, BodyColor);
  Metadata := Message.TimeText.Trim;
  if IsRead then
  begin
    if Metadata <> '' then Metadata := Metadata + '  ';
    Metadata := Metadata + '既読';
  end;
  MetaWidth := Max(Row.Width, 104);
  MetaX := X;
  if Speaker.Outgoing then MetaX := X + Row.Width - MetaWidth;
  TextAt(Target, Metadata, FSmallFont, MetaX, BubbleY + Row.BubbleHeight + 3,
    MetaWidth, 20, Alpha or FData.TextColor, Speaker.Outgoing);
  finally
    Target.Restore(RowState);
  end;
end;

procedure TMineRenderer.Draw(Target: TGPGraphics; const Destination: TRect; TimeMS: Double;
  PhoneColor: ARGB);
var
  State, ClipState: GraphicsState;
  Screen: TGPGraphicsPath;
  Pen: TGPPen;
  I, Visible, TypingDuration, CharacterCount: Integer;
  TypingProgress, Reveal, Scroll, RowBottom, ChatHeight, Y, DraftX,
    DraftRatio, DraftWidth, DraftHeight: Single;
  DraftText: string;
  DraftImage: TGPBitmap;
begin
  if Destination.IsEmpty or (FWidth = 0) then Exit;
  State := Target.Save;
  Screen := nil;
  try
    Target.SetSmoothingMode(SmoothingModeAntiAlias);
    Target.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    Target.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    Target.TranslateTransform(Destination.Left, Destination.Top);
    Target.ScaleTransform(Destination.Width / FWidth, Destination.Height / FHeight);
    FillRound(Target, 1, 1, FWidth - 2, FHeight - 2, 42, $FF101418);
    FillRound(Target, 3, 3, FWidth - 6, FHeight - 6, 40, PhoneColor or $FF000000);
    Screen := RoundPath(14, 18, FWidth - 28, FHeight - 36, 29);
    Target.SetClip(Screen, CombineModeIntersect);
    FillRound(Target, 14, 18, FWidth - 28, FHeight - 36, 29, $FF000000 or FData.BackgroundColor);
    FillRound(Target, 14, 18, FWidth - 28, 104, 1, $FFF5F7F9);
    TextAt(Target, '9:41', FSmallFont, 35, 28, 50, 20, $FF202830);
    // 本体を横へ倒した時は、物理的なカメラ・スピーカー部分も左辺へ回す。
    if FWidth > FHeight then
      FillRound(Target, 26, FHeight / 2 - 42, 16, 84, 8, $FF101418)
    else FillRound(Target, FWidth / 2 - 42, 26, 84, 16, 8, $FF101418);
    FillRound(Target, FWidth - 66, 30, 26, 11, 3, $FF384652);
    FillRound(Target, FWidth - 38, 33, 3, 5, 1, $FF384652);
    TextAt(Target, FData.Title, FHeaderFont, 56, 70, FWidth - 135, 36, $FF172530);
    Pen := TGPPen.Create($FF263641, 2.8);
    try
      Target.DrawLine(Pen, 39, 78, 30, 87);
      Target.DrawLine(Pen, 30, 87, 39, 96);
    finally
      Pen.Free;
    end;
    TextAt(Target, '···', FHeaderFont, FWidth - 54, 70, 34, 34, $FF263641);
    ChatHeight := FHeight - 216;
    ClipState := Target.Save;
    try
      Target.SetClip(MakeRect(Single(14), Single(124), Single(FWidth - 28), ChatHeight), CombineModeIntersect);
      Visible := MineVisibleCount(FData, TimeMS);
      Scroll := 0;
      for I := 0 to Visible - 1 do
      begin
        RowBottom := Max(0, FRows[I].Top + FRows[I].Height - ChatHeight + 8);
        Scroll := Scroll + (RowBottom - Scroll) * MineReveal(FData.Messages[I], TimeMS);
      end;
      for I := 0 to Visible - 1 do
      begin
        Y := 124 + FRows[I].Top - Scroll;
        if (Y + FRows[I].Height < 124) or (Y > 124 + ChatHeight) then Continue;
        Reveal := MineReveal(FData.Messages[I], TimeMS);
        if Reveal > 0 then DrawRow(Target, I, Y, Reveal,
          TimeMS >= FData.Messages[I].ShowMS + MINE_READ_MS);
      end;
    finally
      Target.Restore(ClipState);
    end;
    FillRound(Target, 14, FHeight - 92, FWidth - 28, 74, 1, $FFF5F7F9);
    TextAt(Target, '+', FHeaderFont, 27, FHeight - 82, 30, 34, $FF596875);
    FillRound(Target, 62, FHeight - 82, FWidth - 122, 36, 18, $FFFFFFFF);
    TypingDuration := 0;
    if Visible < Length(FData.Messages) then TypingDuration := MineTypingDuration(FData, Visible);
    if (TypingDuration > 0) and (TimeMS >= FData.Messages[Visible].ShowMS - TypingDuration) then
    begin
      TypingProgress := (TimeMS - (FData.Messages[Visible].ShowMS - TypingDuration)) / TypingDuration;
      DraftText := MineTypingText(FData.Messages[Visible].Text);
      CharacterCount := MineCharacterCount(DraftText);
      DraftText := MineTypedPrefix(DraftText, Floor(TypingProgress * CharacterCount) + 1);
      DraftX := 77;
      if FData.Messages[Visible].PhotoFile <> '' then
      begin
        DraftImage := Picture(FData.Messages[Visible].PhotoFile);
        if DraftImage <> nil then
        begin
          DraftRatio := Min(30 / DraftImage.GetWidth, 24 / DraftImage.GetHeight);
          DraftWidth := DraftImage.GetWidth * DraftRatio;
          DraftHeight := DraftImage.GetHeight * DraftRatio;
          DrawPicture(Target, DraftImage, MakeRect(70 + (30 - DraftWidth) / 2,
            FHeight - 76 + (24 - DraftHeight) / 2, DraftWidth, DraftHeight), 255);
        end;
        DraftX := 110;
        if DraftText = '' then DraftText := '写真を準備中…';
      end;
      if DraftText = '' then DraftText := '入力中…';
      TextAt(Target, DraftText, FBodyFont, DraftX, FHeight - 80,
        FWidth - DraftX - 68, 30, $FF273C32);
      FillRound(Target, 77, FHeight - 49, (FWidth - 155) * TypingProgress, 2, 1, $FF59B879);
      FillRound(Target, FWidth - 52, FHeight - 78, 28, 28, 14, $FF59B879);
      Pen := TGPPen.Create($FFFFFFFF, 2);
      try
        Target.DrawLine(Pen, FWidth - 38, FHeight - 57, FWidth - 38, FHeight - 70);
        Target.DrawLine(Pen, FWidth - 43, FHeight - 65, FWidth - 38, FHeight - 70);
        Target.DrawLine(Pen, FWidth - 33, FHeight - 65, FWidth - 38, FHeight - 70);
      finally
        Pen.Free;
      end;
    end
    else TextAt(Target, 'メッセージを入力', FSmallFont, 77, FHeight - 73,
      FWidth - 155, 23, $FF939DA6);
    FillRound(Target, FWidth / 2 - 54, FHeight - 31, 108, 4, 2, $FF27333E);
  finally
    Screen.Free;
    Target.Restore(State);
  end;
end;

function TMineRenderer.RenderSurface(TimeMS: Double; PhoneColor: ARGB): TGPBitmap;
var
  Target: TGPGraphics;
begin
  if (FSurface = nil) or (Integer(FSurface.GetWidth) <> FWidth) or
    (Integer(FSurface.GetHeight) <> FHeight) then
  begin
    FreeAndNil(FSurface);
    FSurface := TGPBitmap.Create(FWidth, FHeight, PixelFormat32bppARGB);
  end;
  Target := TGPGraphics.Create(FSurface);
  try
    Target.Clear(0);
    Draw(Target, Rect(0, 0, FWidth, FHeight), TimeMS, PhoneColor);
  finally
    Target.Free;
  end;
  Result := FSurface;
end;

end.
