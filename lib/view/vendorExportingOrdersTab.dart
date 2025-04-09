import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VendorExportingOrdersTab extends StatefulWidget {
  final String vendorID;

  const VendorExportingOrdersTab({required this.vendorID});

  @override
  State<VendorExportingOrdersTab> createState() =>
      _VendorExportingOrdersTabState();
}

class _VendorExportingOrdersTabState extends State<VendorExportingOrdersTab> {
  Future<Map<String, dynamic>> _fetchCustomerDetails(String userId) async {
    var userDoc =
    await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.exists ? userDoc.data() as Map<String, dynamic> : {};
  }

  Future<Map<String, dynamic>> _fetchProductDetails(String productId) async {
    var productDoc = await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .get();
    return productDoc.exists ? productDoc.data() as Map<String, dynamic> : {};
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    await FirebaseFirestore.instance
        .collection('exportingOrders')
        .doc(orderId)
        .update({'status': newStatus});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('exportingOrders')
          .where('vendorId', isEqualTo: widget.vendorID)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text("No Exporting Orders"));
        }

        var orders = snapshot.data!.docs;

        return ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            var orderDoc = orders[index];
            var order = orderDoc.data() as Map<String, dynamic>;
            String orderId = orderDoc.id;
            String userId = order['userId'];
            String productId = order['productId'];
            Timestamp timestamp = order['timestamp'];
            String formattedDate = timestamp.toDate().toString();

            Map<String, dynamic> shippingData = order['shippingAddress'] ?? {};
            String fullName = shippingData['fullName'] ?? "No Name";
            String addressLine1 = shippingData['addressLine1'] ?? "No Address";
            String city = shippingData['city'] ?? "No City";
            String state = shippingData['state'] ?? "No State";
            String postalCode =
                shippingData['postalCode'] ?? "No Postal Code";
            String country = shippingData['country'] ?? "No Country";
            String phone = shippingData['phone'] ?? "No Phone";

            String shippingAddress =
                "$fullName, $addressLine1, $city, $state, $postalCode, $country\nPhone: $phone";

            String currentStatus = order['status'] ?? "Pending";

            return FutureBuilder(
              future: Future.wait([
                _fetchCustomerDetails(userId),
                _fetchProductDetails(productId),
              ]),
              builder: (context,
                  AsyncSnapshot<List<Map<String, dynamic>>> detailsSnapshot) {
                if (detailsSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                var customerDetails = detailsSnapshot.data?[0] ?? {};
                var productDetails = detailsSnapshot.data?[1] ?? {};
                List<dynamic> imageList = productDetails['images'] ?? [];
                String imageUrl =
                imageList.isNotEmpty ? imageList.first.toString() : "";

                return Card(
                  margin: EdgeInsets.all(8),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order #$orderId',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 10),
                        if (imageUrl.isNotEmpty)
                          Image.network(imageUrl,
                              height: 100, width: 100, fit: BoxFit.cover),
                        SizedBox(height: 10),
                        Text('Customer: ${customerDetails['name'] ?? "Unknown"}'),
                        Text('Email: ${customerDetails['email'] ?? "No Email"}'),
                        Text('Product: ${productDetails['name'] ?? "Unknown"}'),
                        Text('Order Date: $formattedDate'),
                        SizedBox(height: 10),
                        Text('Delivery Address:\n$shippingAddress'),
                        SizedBox(height: 10),
                        Text('Payment ID: ${order['paymentId'] ?? "No Payment ID"}'),
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Status:",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            DropdownButton<String>(
                              value: currentStatus,
                              items: ['Pending', 'On the Way', 'Delivered']
                                  .map((status) => DropdownMenuItem(
                                value: status,
                                child: Text(status),
                              ))
                                  .toList(),
                              onChanged: (newStatus) {
                                if (newStatus != null) {
                                  _updateOrderStatus(orderId, newStatus);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
