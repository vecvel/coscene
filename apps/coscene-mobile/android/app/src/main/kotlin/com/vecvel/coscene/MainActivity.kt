package com.vecvel.coscene

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter and plays the short sounds that the Dart side synthesises.
 * The app ships no audio files: Dart sends raw 16-bit samples once, and each
 * sound is kept in its own static AudioTrack for low-latency playback.
 */
class MainActivity : FlutterActivity() {
    private val tracks = HashMap<Int, AudioTrack>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coscene/audio")
            .setMethodCallHandler { call, result ->
                val id = call.argument<Int>("id")
                when {
                    id == null -> result.error("bad_args", "Missing sound id", null)
                    call.method == "load" -> {
                        val rate = call.argument<Int>("rate")
                        val pcm = call.argument<ByteArray>("pcm")
                        if (rate == null || pcm == null || pcm.isEmpty()) {
                            result.error("bad_args", "Missing samples", null)
                        } else {
                            load(id, rate, pcm)
                            result.success(null)
                        }
                    }
                    call.method == "play" -> {
                        play(id, (call.argument<Double>("volume") ?: 1.0).toFloat())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun load(id: Int, rate: Int, pcm: ByteArray) {
        tracks.remove(id)?.release()
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(pcm.size)
            .build()
        track.write(pcm, 0, pcm.size)
        tracks[id] = track
    }

    private fun play(id: Int, volume: Float) {
        val track = tracks[id] ?: return
        try {
            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) track.stop()
            track.reloadStaticData()
            track.setVolume(volume)
            track.play()
        } catch (e: IllegalStateException) {
            // The audio system was not ready; the game carries on silently.
        }
    }

    override fun onDestroy() {
        tracks.values.forEach { it.release() }
        tracks.clear()
        super.onDestroy()
    }
}
