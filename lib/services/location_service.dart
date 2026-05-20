import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Unified location service that works on both web (browser Geolocation API
/// via geolocator's web implementation) and mobile (GPS).
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamController<({double lat, double lng})>? _positionController;
  StreamSubscription<Position>? _positionSub;

  /// Request permission and return true if granted.
  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) {
        // On web, geolocator uses the browser Geolocation API.
        // Requesting permission triggers the browser prompt.
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        return perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always;
      } else {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return false;

        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
          if (perm == LocationPermission.denied) return false;
        }
        if (perm == LocationPermission.deniedForever) return false;
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  /// Get the current position once. Returns null if unavailable.
  Future<({double lat, double lng})?> getCurrentPosition() async {
    try {
      final granted = await requestPermission();
      if (!granted) return null;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Stream of position updates. Caller must cancel the subscription.
  Stream<({double lat, double lng})> positionStream() {
    _positionController?.close();
    _positionController =
        StreamController<({double lat, double lng})>.broadcast();

    _positionSub?.cancel();
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
            distanceFilter: kIsWeb ? 10 : 5,
          ),
        ).listen(
          (pos) {
            _positionController?.add((lat: pos.latitude, lng: pos.longitude));
          },
          onError: (_) {},
          cancelOnError: false,
        );

    return _positionController!.stream;
  }

  void dispose() {
    _positionSub?.cancel();
    _positionController?.close();
  }
}
