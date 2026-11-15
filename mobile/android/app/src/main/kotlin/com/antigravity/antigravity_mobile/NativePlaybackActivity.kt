package com.antigravity.antigravity_mobile

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView

@androidx.annotation.OptIn(UnstableApi::class)
class NativePlaybackActivity : Activity() {
    private lateinit var playerView: PlayerView
    private var player: ExoPlayer? = null
    private var positionMs = 0L
    private var playWhenResumed = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        positionMs = savedInstanceState?.getLong(POSITION)
            ?: intent.getLongExtra(POSITION, 0L).coerceAtLeast(0)
        playWhenResumed = savedInstanceState?.getBoolean(PLAYING) ?: true
        playerView = PlayerView(this).apply {
            setBackgroundColor(Color.BLACK)
        }
        setContentView(playerView)
        ViewCompat.setOnApplyWindowInsetsListener(playerView) { view, insets ->
            val padding = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            view.setPadding(padding.left, padding.top, padding.right, padding.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(playerView)
    }

    override fun onStart() {
        super.onStart()
        val uri = intent.data
        if (uri == null) {
            finish()
            return
        }
        val playback = ExoPlayer.Builder(this).build()
        player = playback
        playerView.player = playback
        playback.setAudioAttributes(AudioAttributes.DEFAULT, true)
        playback.setHandleAudioBecomingNoisy(true)
        playback.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                if (isFinishing || isDestroyed) return
                AlertDialog.Builder(this@NativePlaybackActivity)
                    .setMessage(R.string.native_video_unavailable)
                    .setPositiveButton(android.R.string.ok) { _, _ -> finish() }
                    .setOnCancelListener { finish() }
                    .show()
            }
        })
        playback.setMediaItem(MediaItem.fromUri(uri), positionMs)
        playback.prepare()
    }

    override fun onResume() {
        super.onResume()
        player?.playWhenReady = playWhenResumed
    }

    override fun onPause() {
        player?.let {
            playWhenResumed = it.playWhenReady
            it.pause()
        }
        super.onPause()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putLong(POSITION, player?.currentPosition ?: positionMs)
        outState.putBoolean(PLAYING, playWhenResumed)
        super.onSaveInstanceState(outState)
    }

    override fun onStop() {
        positionMs = player?.currentPosition ?: positionMs
        playerView.player = null
        player?.release()
        player = null
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // The Flutter gallery can require authentication when returning from background.
        if (!isChangingConfigurations) finish()
        super.onStop()
    }

    companion object {
        private const val POSITION = "positionMs"
        private const val PLAYING = "playing"

        fun intent(context: Context, uri: Uri, positionMs: Long) =
            Intent(context, NativePlaybackActivity::class.java).apply {
                data = uri
                putExtra(POSITION, positionMs)
            }
    }
}
