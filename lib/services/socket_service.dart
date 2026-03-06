import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../utils/logger.dart';

/// Service for real-time WebSocket communication
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  IO.Socket? get socket => _socket;

  /// Initialize socket connection
  void connect(String baseUrl, String userId, String role) {
    if (_socket != null && _isConnected) {
      Log.d('[SocketService] Already connected');
      return;
    }

    Log.i('[SocketService] Connecting to $baseUrl as $role...');

    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket', 'polling'],
      'autoConnect': true,
      'path': '/socket.io',
    });

    _socket!.onConnect((_) {
      Log.i('[SocketService] ✅ Connected to server');
      _isConnected = true;

      // Join role-specific room
      final roleRoom = '${role}s'; // 'drivers', 'clients', 'admins'
      _socket!.emit('join', {'room': roleRoom});
      Log.i('[SocketService] Joined room: $roleRoom');

      // Join personal room
      _socket!.emit('join', {'room': userId});
      Log.i('[SocketService] Joined personal room: $userId');
    });

    _socket!.onDisconnect((_) {
      Log.w('[SocketService] ⚠️ Disconnected from server');
      _isConnected = false;
    });

    _socket!.onConnectError((data) {
      Log.w('[SocketService] ❌ Connection error: $data');
      _isConnected = false;
    });

    _socket!.onError((error) {
      Log.w('[SocketService] ❌ Socket error: $error');
    });
  }

  /// Listen to new SOS requests (for drivers)
  void onNewSOSRequest(Function(Map<String, dynamic>) callback) {
    // Remove existing listener first to avoid duplicates
    _socket?.off('new_sos_request');
    
    // Add new listener
    _socket?.on('new_sos_request', (data) {
      Log.i('[SocketService] \ud83d\udea8 New SOS request received: $data');
      if (data is Map<String, dynamic>) {
        callback(data);
      } else {
        Log.w('[SocketService] Invalid data type for new_sos_request');
      }
    });
    Log.d('[SocketService] Listener registered for new_sos_request');
  }

  /// Listen to SOS acceptance (for clients)
  void onSOSAccepted(Function(Map<String, dynamic>) callback) {
    _socket?.on('sos_accepted', (data) {
      print('[SocketService] SOS accepted: $data');
      callback(data as Map<String, dynamic>);
    });
  }

  /// Listen to driver location updates
  void onDriverLocationUpdate(String driverId, Function(Map<String, dynamic>) callback) {
    _socket?.emit('join', {'room': 'driver_$driverId'});
    _socket?.on('driver_location_update', (data) {
      Log.d('[SocketService] Driver location update: $data');
      callback(data as Map<String, dynamic>);
    });
  }

  /// Emit driver location update
  void emitDriverLocation(String driverId, double lat, double lng) {
    if (_isConnected) {
      _socket?.emit('driver_location_update', {
        'driver_id': driverId,
        'location': {'lat': lat, 'lng': lng},
      });
    }
  }

  /// Disconnect socket
  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
      _isConnected = false;
    }
  }
}
