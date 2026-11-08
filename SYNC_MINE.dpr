library SYNC_MINE;

// SYNC_MINE の AviUtl2 DLL 境界。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  SYNC_MusicStudio_DarkTheme in 'Source\Lib\SYNC_MusicStudio_DarkTheme.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  RTTIPersistent in '..\AviUtl2Plugin\AviUtl2PluginLib\Lib\RTTIPersistent\RTTIPersistent.pas',
  RTTIPersistentIni in '..\AviUtl2Plugin\AviUtl2PluginLib\Lib\RTTIPersistent\RTTIPersistentIni.pas',
  RTTISectionPersistent in '..\AviUtl2Plugin\AviUtl2PluginLib\Lib\RTTIPersistent\RTTISectionPersistent.pas',
  SectionFileManager in '..\AviUtl2Plugin\AviUtl2PluginLib\Lib\SectionFileManager\SectionFileManager.pas',
  VectorRendererData in '..\AviUtl2Plugin\AviUtl2PluginLib\Lib\VectorRenderer\VectorRendererData.pas',
  VectorRenderer in '..\AviUtl2Plugin\AviUtl2PluginLib\Lib\VectorRenderer\VectorRenderer.pas',
  VectorRendererImageList in '..\AviUtl2Plugin\AviUtl2PluginLib\Lib\VectorRenderer\VectorRendererImageList.pas',
  SYNC_MINE_Conversation in 'Source\Common\Conversation\SYNC_MINE_Conversation.pas',
  SYNC_MINE_UserSettings in 'Source\Common\Settings\SYNC_MINE_UserSettings.pas',
  SYNC_MINE_CharacterIcons in 'Source\Common\Images\SYNC_MINE_CharacterIcons.pas',
  SYNC_MINE_Renderer in 'Source\Common\Render\SYNC_MINE_Renderer.pas',
  SYNC_MINE_DarkControls in 'Source\Lib\UI\SYNC_MINE_DarkControls.pas',
  ColorPickerColorMath in 'Source\Lib\ColorPicker\ColorPickerColorMath.pas',
  ColorPickerHueBar in 'Source\Lib\ColorPicker\ColorPickerHueBar.pas',
  ColorPickerSVArea in 'Source\Lib\ColorPicker\ColorPickerSVArea.pas',
  SYNC_MINE_PaletteEditor in 'Source\Lib\UI\SYNC_MINE_PaletteEditor.pas',
  SYNC_MINE_MessageInput in 'Source\Lib\UI\SYNC_MINE_MessageInput.pas',
  SYNC_MINE_MessageList in 'Source\Lib\UI\SYNC_MINE_MessageList.pas',
  SYNC_MINE_SettingsForm in 'Source\Plugin\Filter\SYNC_MINE_SettingsForm.pas',
  SYNC_MINE_FilterPlugin in 'Source\Plugin\Filter\SYNC_MINE_FilterPlugin.pas';

{$R *.res}
{$R '..\AviUtl2Plugin\AviUtl2PluginLib\Serif\Chara\SerifCharaVectorResource.RES'}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if not StartMineGraphics then Exit;
    GetMineFilterTable;
    Result := 1;
  except
    StopMineGraphics;
    // Delphi 例外を AviUtl2 の C コールバック境界へ漏らさない。
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  StopMineGraphics;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetMineFilterTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
