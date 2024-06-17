import 'package:flutter/material.dart';
import 'package:Safe_travel/navigation_screen.dart';
import 'package:location/location.dart' as loc;

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  loc.Location location = loc.Location();
  loc.LocationData? _currentPosition;

  @override
  void initState() {
    super.initState();
    _navigateToNavigationScreen();
  }

  _navigateToNavigationScreen() async {
    _currentPosition = await location.getLocation();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => NavigationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: NavigationScreen(),
        ),
      ),
    );
  }
}
