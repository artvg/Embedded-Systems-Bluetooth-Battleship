import 'package:flutter/material.dart';

// BLE UUIDs ── must match M5Stack firmware exactly 
const String kServiceUUID   = 'f4893cb2-c54a-4c85-9339-4c03f3f19077';
const String kMoveCharUUID  = 'ceb4ef8c-12b5-4932-b2d5-3bf26fe18af5';
const String kStateCharUUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

// Grid constants 
const int kGridSize      = 6;
const int kShipCount     = 3;   // 3 ships
const int kShipLength    = 2;   // each ship is 2 cells
const int kTotalShipCells = kShipCount * kShipLength; // 6

// Color palette (mirrors M5Stack theme) 
const Color kBg       = Color(0xFF000820);
const Color kWater    = Color(0xFF041C3A);
const Color kGridLine = Color(0xFF0A3A4A);
const Color kShip     = Color(0xFF8AB0C0);
const Color kHit      = Color(0xFFCC2020);
const Color kMiss     = Color(0xFF2A3A4A);
const Color kWhite    = Colors.white;
const Color kGreen    = Color(0xFF00C844);
const Color kRedBan   = Color(0xFFB42800);
const Color kSubtext  = Color(0xFF4A7A8A);
const Color kStatusBg = Color(0xFF08182A);
const Color kCursor   = Color(0xFFFFDC00);
const Color kShipDead = Color(0xFF501414);

//  Typography helper 
const TextStyle kLabelStyle = TextStyle(
  color: kSubtext,
  fontSize: 10,
  fontFamily: 'monospace',
  letterSpacing: 1,
);
