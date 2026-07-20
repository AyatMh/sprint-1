package com.technion.interviewpro.interviewpro

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val channelName = "interviewpro/audio_extractor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAudio" -> {
                        val input = call.argument<String>("inputPath")
                        val output = call.argument<String>("outputPath")
                        val trimStartMs = (call.argument<Number>("trimStartMs"))?.toLong() ?: 0L
                        if (input == null || output == null) {
                            result.error("ARGS", "inputPath and outputPath are required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                extractAudio(input, output, trimStartMs)
                                runOnUiThread { result.success(output) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("EXTRACT_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Demuxes the AAC audio track out of an MP4 into an .m4a container
    // without re-encoding (MediaExtractor -> MediaMuxer). Fast and lossless.
    // trimStartMs, when > 0, seeks past that much lead-in (e.g. the silent
    // calibration countdown) so it's never included in the extracted audio.
    private fun extractAudio(inputPath: String, outputPath: String, trimStartMs: Long) {
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)

        var audioTrackIndex = -1
        var audioFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                audioFormat = format
                break
            }
        }
        if (audioTrackIndex < 0 || audioFormat == null) {
            extractor.release()
            throw IllegalStateException("No audio track found in $inputPath")
        }

        extractor.selectTrack(audioTrackIndex)
        val trimStartUs = trimStartMs * 1000L
        if (trimStartUs > 0) {
            extractor.seekTo(trimStartUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC_SAMPLE)
        }

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val muxerTrack = muxer.addTrack(audioFormat)
        muxer.start()

        val maxSize = if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
        } else {
            256 * 1024
        }
        val buffer = ByteBuffer.allocate(maxSize)
        val info = MediaCodec.BufferInfo()

        while (true) {
            info.size = extractor.readSampleData(buffer, 0)
            if (info.size < 0) break
            val sampleTimeUs = extractor.sampleTime
            info.presentationTimeUs = if (trimStartUs > 0) {
                maxOf(0L, sampleTimeUs - trimStartUs)
            } else {
                sampleTimeUs
            }
            info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                MediaCodec.BUFFER_FLAG_KEY_FRAME
            } else {
                0
            }
            info.offset = 0
            muxer.writeSampleData(muxerTrack, buffer, info)
            extractor.advance()
        }

        muxer.stop()
        muxer.release()
        extractor.release()
    }
}
