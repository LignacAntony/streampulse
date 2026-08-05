import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_capture.dart';

/// Capture AAC/ADTS native avec la configuration voix de StreamPulse.
class RecordAudioCapture implements AudioCapture {
  RecordAudioCapture([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> supportsAacAdts() =>
      _recorder.isEncoderSupported(AudioEncoder.aacLc);

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 44100,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
      audioInterruption: AudioInterruptionMode.pauseResume,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
