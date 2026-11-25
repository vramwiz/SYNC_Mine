unit SYNC_MINE_Audio;

// 効果音を数式から生成し、任意のサンプル区間に重なる発音を合成する。

interface

uses SYNC_MINE_Conversation;

type
  TMineSound = (msSend, msReceive, msKeyLow, msKeyMid, msKeyHigh);
  TMineSoundEvent = record
    StartMS: Double;
    Sound: TMineSound;
  end;

  TMineAudio = class
  private
    FEvents: TArray<TMineSoundEvent>;
    FSampleRate: Integer;
    FWaves: array[TMineSound] of TArray<Single>;
    procedure PrepareWaves(SampleRate: Integer);
  public
    procedure Prepare(const Data: TMineConversation);
    // Volume 100 は生成波形の等倍。発音のない区間では False を返す。
    function Render(StartSample: Int64; Count, SampleRate: Integer; Volume: Double;
      var Samples: TArray<Single>): Boolean;
  end;

implementation

uses System.Generics.Collections, System.Math, SYNC_MINE_Timeline;

const
  SOUND_SECONDS: array[TMineSound] of Double = (0.075, 0.21, 0.022, 0.022, 0.022);

function DampedTone(Time, Frequency, Sweep, Duration, Decay: Double): Double;
begin
  if (Time < 0) or (Time >= Duration) then Exit(0);
  Result := Sin(2 * Pi * (Frequency + Sweep * Time / 2) * Time) * Exp(-Decay * Time) *
    Min(1.0, Time / 0.003) * Min(1.0, (Duration - Time) / 0.008);
end;

procedure TMineAudio.PrepareWaves(SampleRate: Integer);
var
  Sound: TMineSound;
  I: Integer;
  NoiseState: UInt32;
  Time, Value, Noise, LowPass, FilterFactor, Frequency, Envelope: Double;
begin
  if SampleRate = FSampleRate then Exit;
  FSampleRate := 0;
  FilterFactor := 1 - Exp(-2 * Pi * 2300 / SampleRate);
  for Sound := Low(TMineSound) to High(TMineSound) do
  begin
    SetLength(FWaves[Sound], Ceil(SOUND_SECONDS[Sound] * SampleRate));
    NoiseState := UInt32($BCA134F9) xor UInt32(Ord(Sound) * 197);
    LowPass := 0;
    Frequency := 170 + (Ord(Sound) - Ord(msKeyLow)) * 35;
    for I := 0 to High(FWaves[Sound]) do
    begin
      Time := I / SampleRate;
      case Sound of
        msSend:
          Value := 0.48 * DampedTone(Time, 465, 1950, 0.075, 38) +
            0.12 * DampedTone(Time, 930, 3900, 0.057, 60);
        msReceive:
          Value := 0.34 * DampedTone(Time, 760, 0, 0.095, 24) +
            0.40 * DampedTone(Time - 0.052, 1085, 0, 0.158, 22) +
            0.07 * DampedTone(Time - 0.052, 2170, 0, 0.105, 35);
      else
        NoiseState := NoiseState xor (NoiseState shl 13);
        NoiseState := NoiseState xor (NoiseState shr 17);
        NoiseState := NoiseState xor (NoiseState shl 5);
        Noise := (NoiseState shr 16) / 32768 - 1;
        LowPass := LowPass + (Noise - LowPass) * FilterFactor;
        Envelope := Min(1.0, Time / 0.001) * Exp(-190 * Time) *
          Min(1.0, (0.022 - Time) / 0.003);
        Value := (0.14 * LowPass + 0.055 * Sin(2 * Pi * Frequency * Time)) * Envelope;
      end;
      FWaves[Sound][I] := Value;
    end;
  end;
  FSampleRate := SampleRate;
end;

procedure TMineAudio.Prepare(const Data: TMineConversation);
var
  Ordered: TMineConversation;
  Events: TList<TMineSoundEvent>;
  Event: TMineSoundEvent;
  Message: TMineMessage;
  I, Duration, Count, CharacterIndex, Stride: Integer;
  Step: Double;
begin
  Ordered := OrderedMineConversation(Data);
  Events := TList<TMineSoundEvent>.Create;
  try
    for I := 0 to High(Ordered.Messages) do
    begin
      Message := Ordered.Messages[I];
      Duration := MineTypingDuration(Ordered, I);
      if (Duration > 0) and (Message.Text <> '') then
      begin
        Count := MineCharacterCount(MineTypingText(Message.Text));
        Step := Duration / Count;
        Stride := Max(1, Ceil(35 / Step));
        CharacterIndex := 0;
        while CharacterIndex < Count do
        begin
          Event.StartMS := Message.ShowMS - Duration + CharacterIndex * Step;
          Event.Sound := TMineSound(Ord(msKeyLow) + (I + CharacterIndex) mod 3);
          Events.Add(Event);
          Inc(CharacterIndex, Stride);
        end;
      end;
      Event.StartMS := Message.ShowMS;
      if Ordered.Speakers[Message.Speaker].Outgoing then Event.Sound := msSend
      else Event.Sound := msReceive;
      Events.Add(Event);
    end;
    FEvents := Events.ToArray;
  finally
    Events.Free;
  end;
end;

function TMineAudio.Render(StartSample: Int64; Count, SampleRate: Integer; Volume: Double;
  var Samples: TArray<Single>): Boolean;
var
  FirstSample, StopSample, WaveStart, BeginSample, EndSample, Position: Int64;
  I, LowIndex, HighIndex, Middle: Integer;
  Wave: TArray<Single>;
  Gain: Double;
begin
  Result := False;
  if (Length(FEvents) = 0) or (Volume <= 0) or (Count <= 0) or (SampleRate <= 0) then Exit;
  FirstSample := StartSample - Ceil(SOUND_SECONDS[msReceive] * SampleRate);
  StopSample := StartSample + Count;
  LowIndex := 0;
  HighIndex := Length(FEvents);
  while LowIndex < HighIndex do
  begin
    Middle := (LowIndex + HighIndex) div 2;
    if Round(FEvents[Middle].StartMS * SampleRate / 1000) < FirstSample then LowIndex := Middle + 1
    else HighIndex := Middle;
  end;
  for I := LowIndex to High(FEvents) do
  begin
    WaveStart := Round(FEvents[I].StartMS * SampleRate / 1000);
    if WaveStart >= StopSample then Break;
    PrepareWaves(SampleRate);
    Wave := FWaves[FEvents[I].Sound];
    BeginSample := Max(StartSample, WaveStart);
    EndSample := Min(StopSample, WaveStart + Length(Wave));
    if EndSample <= BeginSample then Continue;
    if not Result then
    begin
      SetLength(Samples, Count);
      FillChar(Samples[0], Count * SizeOf(Single), 0);
      Result := True;
    end;
    for Position := BeginSample to EndSample - 1 do
      Samples[Position - StartSample] := Samples[Position - StartSample] + Wave[Position - WaveStart];
  end;
  if not Result then Exit;
  Gain := EnsureRange(Volume, 0.0, 100.0) / 100;
  for I := 0 to Count - 1 do Samples[I] := EnsureRange(Samples[I], -1.0, 1.0) * Gain;
end;

end.
