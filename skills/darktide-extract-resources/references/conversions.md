# Resource Conversions

Use limn's usable output directly unless another format is needed. Tool sources are listed in [Workspace And Tools](tools.md).

## DDS To PNG

Use texconv to convert the extracted DDS to PNG:

```powershell
& '<texconv-executable>' -nologo -ft png -o '<png-directory>' '<texture.dds>'
```

texconv uses the input basename. Preserve resource-relative output directories when processing same-named textures from different paths.

Packed masks and normal maps contain data channels, not ordinary color images. A PNG conversion also does not preserve an entire DDS array, cube map, mip chain, or HDR precision. The [texconv documentation](https://github.com/microsoft/DirectXTex/wiki/Texconv) covers surface/format choices and other image outputs.

## Audio To WAV

When WAV is requested, decode an already extracted OGG directly. vgmstream accepts both OGG and WEM:

```powershell
& '<vgmstream-executable>' -i -o '<output.wav>' '<audio-file>'
```

`-i` decodes once without repeating the stream's loop.

When the original Wwise media is needed, extract it as WEM:

```powershell
& '<limn-executable>' -i '<game>/bundle' -o '<wem-directory>' --dict '<selection.txt>' --config force-wem wwise_stream
```

`force-wem` retrieves the external media; `--dump-raw` only retains its resource representation.

## Embedded Event Audio

A `wwise_event` may embed media or reference external streams. One event can select or layer multiple clips; exporting embedded clips does not reproduce the whole event's in-game behavior.

Extract the selected `wwise_event` with limn, then scan that file:

```powershell
& '<quickbms-executable>' -Y '<wave-scanner.bms>' '<event.wwise_event>' '<media-directory>'
```

The scanner extracts embedded RIFF/RIFX media, not externally referenced streams. Its sequence numbers are not Wwise media IDs. Output extensions such as `.wav`, `.lwav`, and `.at3` are scanner labels, not proof of PCM WAV; Wwise RIFF media can use a temporary `.wem` copy if the label misleads the decoder.

Decode the scanned media with the same vgmstream command, retaining the event/resource association when naming multiple clips.
