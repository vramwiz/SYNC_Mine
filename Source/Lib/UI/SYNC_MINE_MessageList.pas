unit SYNC_MINE_MessageList;

// 複数選択を保った発言一覧。自己ドラッグの挿入線と端でのスクロールを担当する。

interface

uses
  System.Classes, System.Types, Winapi.Messages, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.StdCtrls, SYNC_MINE_Conversation;

type
  TMineMessageReorderEvent = procedure(Sender: TObject; const Indices: TArray<Integer>;
    Destination: Integer) of object;

  TMineMessageList = class(TListBox)
  private
    FDropIndex: Integer;
    FDragIndices: TArray<Integer>;
    FScrollTimer: TTimer;
    FOnReorder: TMineMessageReorderEvent;
    function BoundaryAt(Y: Integer): Integer;
    procedure SetDropIndex(Value: Integer);
    procedure ClearDrop;
    procedure PaintDropLine;
    procedure ScrollDrag(Sender: TObject);
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure DoStartDrag(var DragObject: TDragObject); override;
    procedure DoEndDrag(Target: TObject; X, Y: Integer); override;
    procedure DragCanceled; override;
    procedure DragOver(Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure DragDrop(Source: TObject; X, Y: Integer); override;
    function SelectedIndices: TArray<Integer>;
    function ActiveIndex: Integer;
    procedure SetSelection(const Indices: array of Integer; FocusIndex: Integer);
    procedure SelectOnly(Index: Integer);
    procedure PaintMessage(const Data: TMineConversation; Index: Integer;
      Bounds: TRect; State: TOwnerDrawState);
    property OnReorder: TMineMessageReorderEvent read FOnReorder write FOnReorder;
  end;

// 元の境界位置へ、選択行を順序を保って挿入する。返値は移動後の選択行。
function ReorderMineMessages(var Messages: TArray<TMineMessage>; const Indices: TArray<Integer>;
  Destination: Integer): TArray<Integer>;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, Vcl.Graphics, SYNC_MusicStudio_DarkTheme;

constructor TMineMessageList.Create(AOwner: TComponent);
begin
  inherited;
  FDropIndex := -1;
  MultiSelect := True;
  ExtendedSelect := True;
  DragMode := dmAutomatic;
  FScrollTimer := TTimer.Create(Self);
  FScrollTimer.Enabled := False;
  FScrollTimer.Interval := 100;
  FScrollTimer.OnTimer := ScrollDrag;
end;

function TMineMessageList.SelectedIndices: TArray<Integer>;
var I, Count: Integer;
begin
  SetLength(Result, Items.Count);
  Count := 0;
  for I := 0 to Items.Count - 1 do
    if Selected[I] then
    begin
      Result[Count] := I;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

function TMineMessageList.ActiveIndex: Integer;
var I: Integer;
begin
  Result := ItemIndex;
  if (Result >= 0) and (Result < Items.Count) and Selected[Result] then Exit;
  for I := 0 to Items.Count - 1 do
    if Selected[I] then Exit(I);
  Result := -1;
end;

procedure TMineMessageList.SetSelection(const Indices: array of Integer; FocusIndex: Integer);
var I: Integer;
begin
  ClearSelection;
  for I in Indices do
    if (I >= 0) and (I < Items.Count) then Selected[I] := True;
  if (FocusIndex >= 0) and (FocusIndex < Items.Count) then
  begin
    ItemIndex := FocusIndex;
    SendMessage(Handle, LB_SETANCHORINDEX, FocusIndex, 0);
  end;
end;

procedure TMineMessageList.SelectOnly(Index: Integer);
begin
  SetSelection([Index], Index);
end;

procedure TMineMessageList.WndProc(var Message: TMessage);
var Mode: TDragMode;
begin
  if (Message.Msg = WM_LBUTTONDOWN) and
    ((Message.WParam and (MK_CONTROL or MK_SHIFT)) <> 0) then
  begin
    // 修飾キーでの選択・解除は、VCLの自動ドラッグよりネイティブの選択操作を優先する。
    Mode := DragMode;
    DragMode := dmManual;
    try inherited; finally DragMode := Mode; end;
  end
  else inherited;
  if (Message.Msg = WM_PAINT) and (FDropIndex >= 0) then PaintDropLine;
end;

function TMineMessageList.BoundaryAt(Y: Integer): Integer;
var Index: Integer; R: TRect;
begin
  if Y < 0 then Exit(TopIndex);
  Index := ItemAtPos(Point(2, Min(Y, ClientHeight - 1)), True);
  if Index < 0 then Exit(Items.Count);
  R := ItemRect(Index);
  Result := Index;
  if Y >= (R.Top + R.Bottom) div 2 then Inc(Result);
end;

procedure TMineMessageList.SetDropIndex(Value: Integer);
begin
  if Value = FDropIndex then Exit;
  FDropIndex := Value;
  Invalidate;
  Update;
end;

procedure TMineMessageList.ClearDrop;
begin
  FScrollTimer.Enabled := False;
  SetDropIndex(-1);
end;

procedure TMineMessageList.DoStartDrag(var DragObject: TDragObject);
begin
  FDragIndices := SelectedIndices;
  inherited;
end;

procedure TMineMessageList.DoEndDrag(Target: TObject; X, Y: Integer);
begin
  ClearDrop;
  FDragIndices := nil;
  inherited;
end;

procedure TMineMessageList.DragCanceled;
begin
  if Length(FDragIndices) = 0 then inherited;
  ClearDrop;
  // 自動ドラッグが通常のクリックで終わった時も、選択数と編集状態を同期する。
  Click;
end;

procedure TMineMessageList.DragOver(Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  inherited;
  Accept := (Source = Self) and (Length(FDragIndices) > 0);
  if not Accept or (State = dsDragLeave) then ClearDrop
  else
  begin
    SetDropIndex(BoundaryAt(Y));
    FScrollTimer.Enabled := (Y < ScaleValue(24)) or (Y >= ClientHeight - ScaleValue(24));
  end;
end;

procedure TMineMessageList.DragDrop(Source: TObject; X, Y: Integer);
var Slot: Integer; Indices: TArray<Integer>;
begin
  if (Source = Self) and (Length(FDragIndices) > 0) then
  begin
    Slot := BoundaryAt(Y);
    Indices := Copy(FDragIndices);
    ClearDrop;
    if Assigned(FOnReorder) then FOnReorder(Self, Indices, Slot);
  end;
  inherited;
end;

procedure TMineMessageList.ScrollDrag(Sender: TObject);
var P: TPoint; Previous: Integer;
begin
  GetCursorPos(P);
  P := ScreenToClient(P);
  if not PtInRect(ClientRect, P) or (Length(FDragIndices) = 0) then
  begin
    ClearDrop;
    Exit;
  end;
  Previous := TopIndex;
  if P.Y < ScaleValue(24) then TopIndex := Max(0, Previous - 1)
  else if P.Y >= ClientHeight - ScaleValue(24) then TopIndex := Min(Items.Count - 1, Previous + 1);
  SetDropIndex(BoundaryAt(P.Y));
  if Previous <> TopIndex then
  begin
    Invalidate;
    Update;
  end;
end;

procedure TMineMessageList.PaintDropLine;
var Surface: TCanvas; DC: HDC; R: TRect; Y, Thickness: Integer;
begin
  if not HandleAllocated or (FDropIndex < 0) then Exit;
  if FDropIndex < Items.Count then Y := ItemRect(FDropIndex).Top
  else if Items.Count > 0 then Y := ItemRect(Items.Count - 1).Bottom
  else Y := 1;
  Thickness := Max(2, ScaleValue(3));
  Y := EnsureRange(Y, Thickness div 2, Max(Thickness div 2, ClientHeight - Thickness div 2 - 1));
  DC := GetDC(Handle);
  Surface := TCanvas.Create;
  try
    Surface.Handle := DC;
    Surface.Brush.Color := $009BCF9B;
    R := Rect(ScaleValue(2), Y - Thickness div 2, ClientWidth - ScaleValue(2), Y + (Thickness + 1) div 2);
    Surface.FillRect(R);
  finally
    Surface.Handle := 0;
    Surface.Free;
    ReleaseDC(Handle, DC);
  end;
end;

procedure TMineMessageList.PaintMessage(const Data: TMineConversation; Index: Integer;
  Bounds: TRect; State: TOwnerDrawState);
var TextBounds: TRect; Summary: string;
begin
  if odSelected in State then Canvas.Brush.Color := $0050473B
  else Canvas.Brush.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  Canvas.FillRect(Bounds);
  if (Index < 0) or (Index >= Length(Data.Messages)) then Exit;
  Canvas.Font.Assign(Font);
  if Data.Speakers[Data.Messages[Index].Speaker].Outgoing then Canvas.Font.Color := $00A1E8AC
  else Canvas.Font.Color := $00E8DFD6;
  TextBounds := Bounds;
  InflateRect(TextBounds, -ScaleValue(8), 0);
  TextBounds.Top := Bounds.Top + ScaleValue(3);
  TextBounds.Bottom := TextBounds.Top + ScaleValue(20);
  SelectObject(Canvas.Handle, Canvas.Font.Handle);
  SetTextColor(Canvas.Handle, ColorToRGB(Canvas.Font.Color));
  SetBkMode(Canvas.Handle, TRANSPARENT);
  DrawText(Canvas.Handle, PChar(Format('%d  %s', [Index + 1,
    Data.Speakers[Data.Messages[Index].Speaker].Name])), -1, TextBounds,
    DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Summary := Data.Messages[Index].Text.Replace(#13, ' ').Replace(#10, ' ');
  if Data.Messages[Index].PhotoFile <> '' then Summary := '写真  ' + Summary;
  if Summary = '' then Summary := '（入力待ち）';
  TextBounds.Top := Bounds.Top + ScaleValue(24);
  TextBounds.Bottom := Bounds.Bottom - ScaleValue(3);
  SetTextColor(Canvas.Handle, ColorToRGB(SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR));
  DrawText(Canvas.Handle, PChar(Summary), -1, TextBounds,
    DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
end;

function ReorderMineMessages(var Messages: TArray<TMineMessage>; const Indices: TArray<Integer>;
  Destination: Integer): TArray<Integer>;
var
  Selected: TArray<Boolean>;
  Reordered: TArray<TMineMessage>;
  I, Count, InsertAt, Cursor: Integer;
begin
  SetLength(Selected, Length(Messages));
  Count := 0;
  InsertAt := 0;
  Destination := EnsureRange(Destination, 0, Length(Messages));
  for I in Indices do
    if (I >= 0) and (I < Length(Messages)) and not Selected[I] then
    begin
      Selected[I] := True;
      Inc(Count);
    end;
  if Count = 0 then Exit(nil);
  for I := 0 to Destination - 1 do
    if not Selected[I] then Inc(InsertAt);
  SetLength(Reordered, Length(Messages));
  SetLength(Result, Count);
  Cursor := InsertAt;
  for I := 0 to High(Messages) do
    if Selected[I] then
    begin
      Reordered[Cursor] := Messages[I];
      Result[Cursor - InsertAt] := Cursor;
      Inc(Cursor);
    end;
  Cursor := 0;
  for I := 0 to High(Messages) do
    if not Selected[I] then
    begin
      if Cursor = InsertAt then Inc(Cursor, Count);
      Reordered[Cursor] := Messages[I];
      Inc(Cursor);
    end;
  Messages := Reordered;
end;

end.
