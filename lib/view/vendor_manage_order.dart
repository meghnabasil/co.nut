import 'package:dup/view/venddrOrdersTab.dart';
import 'package:dup/view/vendorExportingOrdersTab.dart';
import 'package:dup/view/vendorSubscriptionOrdersTab.dart';
import 'package:flutter/material.dart';
import '../controller/session.dart';

class ManageOrdersPage extends StatefulWidget {
  @override
  _ManageOrdersPageState createState() => _ManageOrdersPageState();
}

class _ManageOrdersPageState extends State<ManageOrdersPage> {
  final Color primaryColor = Color(0xFF033015);
  String? vendorID;

  @override
  void initState() {
    super.initState();
    _getVendorID();
  }

  void _getVendorID() async {
    final sessionData = await Session.getVendor();
    setState(() {
      vendorID = sessionData['vid'];
      print("Vendor Data: $vendorID");
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Manage Orders',
            style: TextStyle(color: Colors.white),
          ),
          iconTheme: IconThemeData(color: Colors.white),
          backgroundColor: primaryColor,
          bottom: TabBar(
            indicatorColor: Colors.brown,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: "Orders"),
              Tab(text: "Exporting"),
              Tab(text: "Subscription"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            vendorID != null
                ?VendorOrdersTab(vendorID: vendorID!)
                : Center(child: CircularProgressIndicator()),
            vendorID != null
                ? VendorExportingOrdersTab(vendorID: vendorID!)
                : Center(child: CircularProgressIndicator()),
            vendorID != null
                ? VendorSubscriptionOrderTabs(vendorID: vendorID!)
                :Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}