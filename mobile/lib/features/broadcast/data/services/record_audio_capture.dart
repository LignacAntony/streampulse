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
      // Service de premier plan Android : c'est lui qui maintient la capture
      // quand le diffuseur quitte l'application (ADR 049). Sans lui, Android
      // coupe l'accès au micro dès que le processus n'est plus au premier plan
      // et le direct devient silencieux sans que rien ne le signale.
      //
      // La notification qu'il affiche n'est pas décorative : c'est l'exigence
      // système, et c'est aussi ce qui rend la diffusion visible et
      // interrompable pendant qu'on est ailleurs sur le téléphone.
      //
      // ignore: deprecated_member_use — `record` pousse vers un package externe
      // de service de premier plan. Y passer ajouterait une dépendance et un
      // service à gérer à la main pour exactement le même résultat ; à revoir
      // quand le champ disparaîtra (prochaine version majeure de `record`).
      androidConfig: AndroidRecordConfig(
        service: AndroidService(
          title: 'StreamPulse — diffusion en cours',
          content: 'Votre microphone est diffusé en direct',
        ),
      ),
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
