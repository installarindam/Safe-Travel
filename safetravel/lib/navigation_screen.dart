import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:location/location.dart' as loc;
import 'package:geocoder2/geocoder2.dart';
import 'package:supabase/supabase.dart';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

double currentSpeed = 0.0;

class NavigationScreen extends StatefulWidget {
  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final TextEditingController _destinationController = TextEditingController();
  final Completer<GoogleMapController?> _controller = Completer();
  Map<PolylineId, Polyline> polylines = {};
  PolylinePoints polylinePoints = PolylinePoints();
  loc.Location location = loc.Location();
  List<CameraDescription>? cameras;
  CameraController? controller;
  late CameraDescription firstCamera;
  late CameraDescription secondCamera;
  Marker? sourcePosition, destinationPosition;
  loc.LocationData? _currentPosition;
  LatLng curLocation = LatLng(23.0525, 72.5667);
  List<Marker> accidentMarkers = [];
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
    fetchAccidentData();

    updateSpeed();
    _markers = Set<Marker>();
    availableCameras().then((availableCameras) {
      cameras = availableCameras;

      if (cameras!.length > 0) {
        firstCamera = cameras![0];
        if (cameras!.length > 1) {
          secondCamera = cameras![1];
        }
        _initializeCamera(firstCamera);
      }
    }).catchError((err) {
      print('Error: $err');
    });
  }
  XFile? _incidentImage; // Store the captured image

  void _showReportDialog() {
    getCurrentLocation();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
            title: Text('Report an Issue'),
            content: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    Text('Describe the issue:'),
                SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Accident at XYZ road',
                  ),
                  maxLines: 3,
                ),
                SizedBox(height: 20),
                Text('Current Location: ${curLocation.latitude}, ${curLocation.longitude}'),
                SizedBox(height: 10),
                if (_incidentImage != null) Image.file(File(_incidentImage!.path))
                else Container(
    width: 300,
    height: 300,
    child: CameraPreview(controller!),
    ),
    ElevatedButton.icon(
    icon: Icon(Icons.camera),
    label: Text('Capture Incident Image'),
    onPressed: () async {
    final XFile? file = await _captureIncidentImage();
    setState(() {
    _incidentImage = file;
    });
    },
    ),
    ElevatedButton(
    onPressed: () {
    // Handle the submission logic here, including the image
    Navigator.pop(context);
    _showConfirmationDialog();
    dispose();

    },
    child: Text('Submit'),
    ),
    ],
    ),
    ),
    ),
    );
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      // Add this line to ensure the flash is off by default

    );

    await controller!.initialize();
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  Future<XFile?> _captureIncidentImage() async {
    if (controller == null || !controller!.value.isInitialized) {
      // If not initialized, initialize the camera
      await _initializeCamera(firstCamera);
    }

    XFile? file;
    try {
      file = await controller!.takePicture();
    } catch (e) {
      print("Error capturing image: $e");
    }

    return file;
  }
  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Thank You!'),
        content: Text('Report submitted. Will be checked and added.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
  void _playWarningSound() async {
    AssetsAudioPlayer.newPlayer().open(
      Audio("assets/alert.mp3"),
      autoStart: true,
      showNotification: true,
    );
  }
  void _showSpeedAlert() {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You just crossed the speed limit !'),
          duration: Duration(seconds: 5),
        )
    );
  }
  getCurrentLocation() async {
    _currentPosition = await location.getLocation();
    setState(() {
      curLocation = LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);
      sourcePosition = Marker(
        markerId: MarkerId('source'),
        position: curLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(title: 'Your location'),
      );
    });

    _animateCameraToCurrentLocation();
    _checkProximityToAccidents();
  }

  void _animateCameraToCurrentLocation() async {
    final GoogleMapController? controller = await _controller.future;
    controller?.animateCamera(
      CameraUpdate.newLatLngZoom(curLocation, 16.0),
    );
  }

  searchDestination() async {
    try {
      GeoData data = await Geocoder2.getDataFromAddress(
          address: _destinationController.text,
          googleMapApiKey: "AIzaSyBX-uyvUK_nVE79IP-ISwTN-HuBz3JDt6k"
      );
      if (data != null) {
        LatLng destinationLatLng = LatLng(data.latitude!, data.longitude!);
        _setDestinationOnTap(destinationLatLng);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Destination not found!')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error occurred!')));
    }
  }

  _setDestinationOnTap(LatLng latLng) {
    setState(() {
      destinationPosition = Marker(
        markerId: MarkerId('destination'),
        position: latLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(title: 'Destination'),
      );
    });
    getDirections(latLng);
  }
  void _recenter() async {
    final GoogleMapController? controller = await _controller.future;
    controller?.animateCamera(
      CameraUpdate.newLatLngZoom(curLocation, 16.0),
    );
  }
  Future<Map<String, dynamic>> fetchWeatherData(double latitude, double longitude) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('No internet connection');
      }

      const apiKey = '08665c3d8a1d470691e64928230209'; // Replace with your WeatherAPI key
      final response = await http.get(
        Uri.parse('http://api.weatherapi.com/v1/current.json?key=$apiKey&q=$latitude,$longitude'),
      );

      if (response.statusCode == 200) {
        print("Weather report");
        print(response);
        return json.decode(response.body);
      } else {
        // Providing detailed error feedback
        throw Exception('Failed to load weather data. HTTP Status Code: ${response.statusCode}, Response Body: ${response.body}');
      }
    } catch (error) {
      print('Error fetching weather data: $error');
      throw error;
    }
  }

  Future<BitmapDescriptor> getWeatherIcon(String condition) async {
    String assetName;

    switch (condition.toLowerCase()) {
      case 'sunny':
        assetName = 'assets/sunny.png';
        break;
      case 'rainy':
        assetName = 'assets/rain.png';
        break;
    // ... add more cases as necessary ...
      default:
        assetName = 'assets/default.png'; // Default weather icon
    }

    return BitmapDescriptor.fromAssetImage(
        ImageConfiguration(devicePixelRatio: 2.5), assetName);
  }
  getDirections(LatLng dst) async {
    List<LatLng> polylineCoordinates = [];
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        'AIzaSyBX-uyvUK_nVE79IP-ISwTN-HuBz3JDt6k',
        PointLatLng(curLocation.latitude, curLocation.longitude),
        PointLatLng(dst.latitude, dst.longitude),
        travelMode: TravelMode.driving);

    if (result.points.isNotEmpty) {
      result.points.forEach((PointLatLng point) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });
      addPolyLine(polylineCoordinates);

      for (int i = 0; i < polylineCoordinates.length; i += 10) {
        final LatLng point = polylineCoordinates[i];
        final weatherData = await fetchWeatherData(point.latitude, point.longitude);

        // Assuming 'condition' is the key in the API response that gives weather condition
        final condition = weatherData['current']['condition']['text'];

        final marker = Marker(
          markerId: MarkerId('marker$i'),
          position: point,
          icon: await getWeatherIcon(condition),
          infoWindow: InfoWindow(title: condition), // This displays the one-word weather condition when the marker is tapped
        );

        // Add marker to the map
        setState(() {
          _markers.add(marker); // Assuming _markers is a set of Marker you have in your StatefulWidget
        });
      }

    } else {
      print(result.errorMessage);
    }
  }

  addPolyLine(List<LatLng> polylineCoordinates) {
    PolylineId id = PolylineId('poly');
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.blue,
      points: polylineCoordinates,
      width: 5,
    );
    polylines[id] = polyline;
    setState(() {});
  }

  fetchAccidentData() async {
    final client = SupabaseClient('https://jyvwwvmfrydopwxhrowg.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp5dnd3dm1mcnlkb3B3eGhyb3dnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTY5MzU4MDg1MSwiZXhwIjoyMDA5MTU2ODUxfQ.h_mRAvn-mMJgVhL_6uhG8VPg1yRiqXz0SS1OGrXuEVI');
    final response = await client.from('accidents').select().execute();
    ImageConfiguration config = ImageConfiguration();
    BitmapDescriptor customIcon = await BitmapDescriptor.fromAssetImage(config, 'assets/car_acci.png');

    if (response.status == 200) {
      List data = response.data;
      for (var item in data) {
        double lat = item['Latitude'];
        double long = item['Longitude'];

        Marker accidentMarker = Marker(
          markerId: MarkerId(item['id'].toString()),
          position: LatLng(lat, long),
          icon: customIcon,
          infoWindow: InfoWindow(title: 'Accident Zone', snippet: item['Reason of Accident']),
        );
        accidentMarkers.add(accidentMarker);
      }
    }
      setState(() {});
    }


  void _checkProximityToAccidents() {
    if (_currentPosition != null) {
      for (var marker in accidentMarkers) {
        double distance = _calculateDistance(_currentPosition!.latitude!, _currentPosition!.longitude!, marker.position.latitude, marker.position.longitude);
        if (distance < 1000) { // considering 1 km as the warning distance
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You are approaching an accident zone!')));
          break;
        }
      }
    }
  }

  double _calculateDistance(double lat1, double long1, double lat2, double long2) {
    // Haversine formula to calculate the distance between two coordinates
    const R = 6371e3; // Earth radius in meters
    var radLat1 = lat1 * (3.14159 / 180);
    var radLat2 = lat2 * (3.14159 / 180);
    var deltaLat = (lat2 - lat1) * (3.14159 / 180);
    var deltaLong = (long2 - long1) * (3.14159 / 180);

    var a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(radLat1) * cos(radLat2) * sin(deltaLong / 2) * sin(deltaLong / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // in meters
  }
  void updateSpeed() async {
    location.onLocationChanged.listen((loc.LocationData currentLocation) {
      setState(() {
        currentSpeed = (currentLocation.speed ?? 0.0) * 3.6;
        // Convert m/s to km/h // if speed is null, then default to 0.0
        if (currentSpeed >= 3) {
          // Play a ringtone or sound here
          _showSpeedAlert();
          _playWarningSound();
        }
      });
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            zoomControlsEnabled: false,
            polylines: Set<Polyline>.of(polylines.values),
            initialCameraPosition: CameraPosition(target: curLocation, zoom: 16),
            markers: {
              if (sourcePosition != null) sourcePosition!,
              if (destinationPosition != null) destinationPosition!,
              ...accidentMarkers,
              ..._markers,
            },
            onTap: _setDestinationOnTap,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
          ),
          Positioned(
            top: 30.0,
            left: 15.0,
            right: 15.0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 5.0,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: TextField(
                controller: _destinationController,
                decoration: InputDecoration(
                  hintText: 'Enter destination',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.directions),
                    onPressed: searchDestination,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 200.0,  // initial position, adjust as needed
            left: 15.0,
            child: GestureDetector(
              child: draggableSpeedRectangle(),
            ),
          ),
          Positioned(
            top: 30,
            left: 15,
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
              },
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.arrow_back, color: Colors.black),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.blue),
              child: IconButton(
                icon: Icon(
                  Icons.navigation_outlined,
                  color: Colors.white,
                ),
                onPressed: () {
                  if (destinationPosition != null) {
                    getDirections(destinationPosition!.position);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please select a destination first!')));
                  }
                },
              ),
            ),
          ),
          Positioned(
            bottom: 150,  // adjust position as needed
            right: 10,
            child: FloatingActionButton(
              child: Icon(Icons.report),
              onPressed: _showReportDialog,
            ),
          ),
          Positioned(
            bottom: 80,  // adjust position as needed
            right: 10,
            child: FloatingActionButton(
              child: Icon(Icons.my_location),
              onPressed: _recenter,
            ),
          ),
        ],
      ),
    );
  }

  Widget draggableSpeedRectangle() {
    return Draggable(
      feedback: speedRectangle(), // The widget appearance when dragging.
      child: speedRectangle(), // The widget appearance in its normal position.
      childWhenDragging: Container(), // Empty container, so it looks like it disappeared when dragging.
      onDragEnd: (dragDetails) {
        // Handle what happens when the drag ends, if needed.
      },
    );
  }

  Widget speedRectangle() {
    return Container(
      width: 100,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Center(
        child: Text(
          '${currentSpeed.toStringAsFixed(2)} km/h',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>> fetchWeatherData(double lat, double lon) async {
  final apiKey = '08665c3d8a1d470691e64928230209';
  final url = 'http://api.weatherapi.com/v1/current.json?key=$apiKey&q=$lat,$lon';

  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    throw Exception('Failed to fetch weather data');
  }
}
