package dev.perpaterb.ev3_controller

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID

/**
 * Bluetooth Classic (SPP/RFCOMM) bridge to the EV3 brick, exposed to Dart
 * over a method channel ("bricklogic/bt") plus an event channel for the
 * incoming byte stream. One connection at a time.
 */
class MainActivity : FlutterActivity() {
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var socket: BluetoothSocket? = null
    private var output: OutputStream? = null
    private var readerThread: Thread? = null
    private var eventSink: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter?
        get() = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "bricklogic/bt/input")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bricklogic/bt")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensurePermission" -> result.success(ensurePermission())
                    "bondedDevices" -> bondedDevices(result)
                    "connect" -> connect(call.argument<String>("address"), result)
                    "write" -> write(call.arguments as? ByteArray, result)
                    "disconnect" -> {
                        closeConnection()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** BLUETOOTH_CONNECT is a runtime permission from Android 12 on. */
    private fun ensurePermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val permission = Manifest.permission.BLUETOOTH_CONNECT
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return true
        requestPermissions(arrayOf(permission), 7001)
        // Returns the pre-dialog state; Dart simply asks again after the
        // user has answered the system prompt.
        return false
    }

    private fun bondedDevices(result: MethodChannel.Result) {
        try {
            val devices = adapter?.bondedDevices?.map {
                mapOf("name" to (it.name ?: "Unknown"), "address" to it.address)
            } ?: emptyList()
            result.success(devices)
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        }
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        if (address == null) {
            result.error("bad_args", "Missing address", null)
            return
        }
        Thread {
            try {
                closeConnection()
                val device = adapter?.getRemoteDevice(address)
                    ?: throw IllegalStateException("Bluetooth is off")
                adapter?.cancelDiscovery()
                val newSocket = device.createRfcommSocketToServiceRecord(sppUuid)
                newSocket.connect()
                socket = newSocket
                output = newSocket.outputStream
                startReader(newSocket)
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                closeConnection()
                runOnUiThread { result.error("connect_failed", e.message, null) }
            }
        }.start()
    }

    private fun startReader(socket: BluetoothSocket) {
        readerThread = Thread {
            val buffer = ByteArray(1024)
            try {
                val input = socket.inputStream
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    val chunk = buffer.copyOf(n)
                    runOnUiThread { eventSink?.success(chunk) }
                }
            } catch (_: Exception) {
                // Falls through to end-of-stream below.
            }
            runOnUiThread { eventSink?.endOfStream() }
        }.also { it.start() }
    }

    private fun write(bytes: ByteArray?, result: MethodChannel.Result) {
        try {
            output?.write(bytes ?: ByteArray(0))
            result.success(null)
        } catch (e: Exception) {
            result.error("write_failed", e.message, null)
        }
    }

    private fun closeConnection() {
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
        output = null
        readerThread = null
    }

    override fun onDestroy() {
        closeConnection()
        super.onDestroy()
    }
}
