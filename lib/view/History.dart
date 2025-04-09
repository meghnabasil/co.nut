import 'package:dup/view/Booking_history.dart';
import 'package:dup/view/bottomnav.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'orderHistoryScreen.dart';

class History extends StatefulWidget {
  const History({super.key});

  @override
  State<History> createState() => _HistoryState();
}

class _HistoryState extends State<History> {
  String? userId;

  @override
  void initState() {
    super.initState();
    _getUserId();
  }

  void _getUserId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        userId = user.uid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Color(0xFF033015),
          iconTheme: IconThemeData(color: Colors.white),
          toolbarHeight: 80,
          title: Image.asset(
            'asset/img.png',
            height: 19,
          ),
          centerTitle: true ,
          leading: IconButton(
            icon: Icon(Icons.home),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => BottomBarScreen()),
                    (route) => false,
              );
            },
          ),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(50),
            child: Container(
              color: Color(0xFF033015),
              child: TabBar(
                indicatorColor: Colors.white,
                indicatorWeight: 4,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelPadding: EdgeInsets.symmetric(horizontal: 10.0),
                tabs: const [
                  Tab(icon: Icon(Icons.history), text: 'Order History'),
                  Tab(icon: Icon(Icons.delivery_dining), text: 'Booking History'),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  userId != null
                      ? CombinedOrderHistoryScreen(userId: userId!)
                      : const Center(child: CircularProgressIndicator()),
                  userId != null
                      ? BookingHistoryScreen(userId: userId!)
                      : const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
