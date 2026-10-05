import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../domain/speech_timeline.dart';

class VideoLessonData {
  const VideoLessonData({
    required this.id,
    required this.courseId,
    required this.title,
    required this.characterId,
    required this.sourceType,
    this.text,
    this.voice,
    this.audioUrl,
    this.durationMs,
    required this.status,
    this.error,
    this.timeline,
  });

  factory VideoLessonData.fromJson(Map<String, dynamic> j) => VideoLessonData(
        id: j['id'] as String,
        courseId: j['courseId'] as String,
        title: j['title'] as String,
        characterId: j['characterId'] as String? ?? 'cloud',
        sourceType: j['sourceType'] as String? ?? 'audio',
        text: j['text'] as String?,
        voice: j['voice'] as String?,
        audioUrl: j['audioUrl'] as String?,
        durationMs: (j['durationMs'] as num?)?.toInt(),
        status: j['status'] as String? ?? 'empty',
        error: j['error'] as String?,
        timeline: j['timeline'] is Map<String, dynamic> ? SpeechTimeline.fromJson(j['timeline'] as Map<String, dynamic>) : null,
      );

  final String id;
  final String courseId;
  final String title;
  final String characterId;
  /// 'audio' | 'text'
  final String sourceType;
  final String? text;
  final String? voice;
  final String? audioUrl;
  final int? durationMs;
  /// 'empty' | 'ready' | 'error'
  final String status;
  final String? error;
  final SpeechTimeline? timeline;
}

class TtsVoice {
  const TtsVoice(this.id, this.label);
  final String id;
  final String label;
}

class VideoLessonsRepository {
  VideoLessonsRepository(this._api);
  final ApiClient _api;

  String _base(String courseId) => '/api/builder/courses/${Uri.encodeComponent(courseId)}/video-lessons';

  VideoLessonData _one(Map<String, dynamic> res) => VideoLessonData.fromJson(res['videoLesson'] as Map<String, dynamic>);

  Future<List<VideoLessonData>> list(String courseId) async {
    final res = await _api.get(_base(courseId));
    return [for (final v in (res['videoLessons'] as List<dynamic>)) VideoLessonData.fromJson(v as Map<String, dynamic>)];
  }

  Future<VideoLessonData> create(String courseId, String title) async => _one(await _api.post(_base(courseId), body: {'title': title}));

  Future<VideoLessonData> get(String courseId, String id) async => _one(await _api.get('${_base(courseId)}/$id'));

  Future<VideoLessonData> update(String courseId, String id, Map<String, dynamic> changes) async =>
      _one(await _api.patch('${_base(courseId)}/$id', body: changes));

  Future<void> delete(String courseId, String id) => _api.delete('${_base(courseId)}/$id');

  /// Uploads the audio and returns the lesson with its fresh speech timeline.
  Future<VideoLessonData> uploadAudio(String courseId, String id, {required List<int> bytes, required String filename}) async =>
      _one(await _api.postMultipart('${_base(courseId)}/$id/audio', fieldName: 'audio', bytes: bytes, filename: filename));

  /// Voices the text on the server (TTS) and analyses it.
  Future<VideoLessonData> synthesize(String courseId, String id, {required String text, required String voice}) async =>
      _one(await _api.postSlow('${_base(courseId)}/$id/tts', body: {'text': text, 'voice': voice}));

  Future<List<TtsVoice>> voices() async {
    final res = await _api.get('/api/builder/tts/voices');
    return [for (final v in (res['voices'] as List<dynamic>)) TtsVoice(v['id'] as String, v['label'] as String)];
  }

  String audioUrl(String? path) => _api.assetUrl(path);
}

final videoLessonsRepositoryProvider = Provider<VideoLessonsRepository>((ref) => VideoLessonsRepository(ref.watch(apiClientProvider)));
