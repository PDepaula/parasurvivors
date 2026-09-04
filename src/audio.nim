## All sound is synthesised at startup: paramidi scores → PCM → WAV bytes → miniaudio sounds.

type
  Sfx* = enum
    SfxHit, SfxGem, SfxLevelUp, SfxHurt, SfxBoss, SfxChest, SfxMusic

when defined(noaudio):
  proc initAudio*() = discard
  proc play*(s: Sfx) = discard
  proc startMusic*() = discard
  proc stopMusic*() = discard
else:
  import parasound/miniaudio, parasound/dr_wav
  import paramidi, paramidi/tsf, paramidi_soundfonts

  # bindings parasound does not expose; the symbols live in its compiled miniaudio.c
  proc ma_sound_seek_to_pcm_frame(pSound: pointer, frameIndex: uint64): ma_result {.cdecl, importc.}
  proc ma_sound_set_looping(pSound: pointer, isLooping: uint32) {.cdecl, importc.}
  proc ma_sound_set_volume(pSound: pointer, volume: cfloat) {.cdecl, importc.}

  const sampleRate = 44100

  var
    engine: seq[uint8]
    wavs: array[Sfx, seq[uint8]]
    decoders: array[Sfx, seq[uint8]]
    sounds: array[Sfx, seq[uint8]]
    ready = false

  proc toWav(data: var seq[cshort]): seq[uint8] =
    # same as parasound/tests/common.nim writeMemory
    var
      wav = newSeq[uint8](drwav_size())
      format: drwav_data_format
    format.container = drwav_container_riff
    format.format = DR_WAVE_FORMAT_PCM
    format.channels = 1
    format.sampleRate = sampleRate
    format.bitsPerSample = 16
    var
      outputRaw: pointer
      outputSize: csize_t
    let frames = data.len.uint32
    doAssert drwav_init_memory_write_sequential(wav[0].addr, outputRaw.addr, outputSize.addr, format.addr, frames, nil)
    doAssert frames == drwav_write_pcm_frames(wav[0].addr, frames, data[0].addr)
    result = newSeq[uint8](outputSize)
    copyMem(result[0].addr, outputRaw, outputSize)
    drwav_free(outputRaw, nil)
    discard drwav_uninit(wav[0].addr)

  proc renderScore(sf: ptr tsf, events: seq[Event]): seq[uint8] =
    var res = render[cshort](events, sf, sampleRate)
    toWav(res.data)

  proc initAudio*() =
    engine = newSeq[uint8](ma_engine_size())
    if MA_SUCCESS != ma_engine_init(nil, engine[0].addr):
      echo "audio: engine init failed, continuing silently"
      return
    when defined(release):
      const soundfont = staticRead("paramidi_soundfonts/generaluser.sf2")
      var sf = tsf_load_memory(soundfont.cstring, soundfont.len.cint)
    else:
      let path = paramidi_soundfonts.getSoundFontPath("generaluser.sf2")
      var sf = tsf_load_filename(path.cstring)
    if sf == nil:
      echo "audio: soundfont not found, continuing silently"
      return
    tsf_set_output(sf, TSF_MONO, sampleRate, 0)
    wavs[SfxHit] = renderScore(sf, compile((marimba, (octave: 5), 1/32, c)))
    wavs[SfxGem] = renderScore(sf, compile((glockenspiel, (octave: 6), 1/32, e, g)))
    wavs[SfxLevelUp] = renderScore(sf, compile((glockenspiel, (octave: 5), 1/16, c, e, g, +c)))
    wavs[SfxHurt] = renderScore(sf, compile((timpani, (octave: 2), 1/16, c)))
    wavs[SfxBoss] = renderScore(sf, compile((orchestra_hit, (octave: 3), 1/8, c)))
    wavs[SfxChest] = renderScore(sf, compile((tubular_bells, (octave: 4), 1/8, c, 1/4, g)))
    wavs[SfxMusic] = renderScore(sf, compile(
      ((mode: concurrent),
       (piano, (tempo: 150), (octave: 3), 1/8,
        a, e, +a, e, +c, e, +a, e,
        f, +c, +f, +c, +d, +c, +f, +c,
        g, +d, +g, +d, +b, +d, +g, +d,
        e, b, +e, b, +gx, b, +e, b),
       (synth_bass_1, (tempo: 150), (octave: 2), 1/4,
        a, a, f, f, g, g, e, e))))
    tsf_close(sf)
    for s in Sfx:
      decoders[s] = newSeq[uint8](ma_decoder_size())
      if MA_SUCCESS != ma_decoder_init_memory(wavs[s][0].addr, wavs[s].len.csize_t, nil, decoders[s][0].addr):
        echo "audio: decoder failed for ", s
        return
      sounds[s] = newSeq[uint8](ma_sound_size())
      if MA_SUCCESS != ma_sound_init_from_data_source(engine[0].addr, decoders[s][0].addr, 0, nil, sounds[s][0].addr):
        echo "audio: sound failed for ", s
        return
      ma_sound_set_volume(sounds[s][0].addr, if s == SfxMusic: 0.35 elif s == SfxHit: 0.4 else: 0.8)
    ma_sound_set_looping(sounds[SfxMusic][0].addr, 1)
    ready = true

  proc play*(s: Sfx) =
    if not ready:
      return
    discard ma_sound_seek_to_pcm_frame(sounds[s][0].addr, 0)
    discard ma_sound_start(sounds[s][0].addr)

  proc startMusic*() =
    if ready:
      discard ma_sound_start(sounds[SfxMusic][0].addr)

  proc stopMusic*() =
    if ready:
      discard ma_sound_stop(sounds[SfxMusic][0].addr)
