import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dup/controller/session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'orderConfirmationPage.dart';

class ShippingAddress extends StatefulWidget {
  final List<String> productIds;
  final List<int> quantities;
  final double totalPrice;

  const ShippingAddress({
    Key? key,
    required this.productIds,
    required this.quantities,
    required this.totalPrice,
  }) : super(key: key);

  @override
  State<ShippingAddress> createState() => _ShippingAddressState();
}

class _ShippingAddressState extends State<ShippingAddress> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _zipController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  List<Map<dynamic, dynamic>> products = [];
  bool isLoading = true;
  late Razorpay _razorpay;
  bool isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    fetchProductDetails();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  Future<void> fetchProductDetails() async {
    try {
      List<Map<dynamic, dynamic>> productList = [];
      for (String productId in widget.productIds) {
        print("Fetch Product Details.: .......... ${widget.productIds}");
        DocumentSnapshot productSnapshot = await FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .get();

        if (productSnapshot.exists) {
          productList.add({
            'id': productId,
            'name': productSnapshot['name'],
            'price': productSnapshot['price'],
            'imageUrl': (productSnapshot['images'] is List<dynamic> && productSnapshot['images'].isNotEmpty)
                ? productSnapshot['images'][0]
                : '',
            'vendorId':productSnapshot['vendorId'],
          });
        }
      }

      setState(() {
        products = productList;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching product details: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _countryController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      setState(() => isProcessingPayment = true);
      _openRazorpayCheckout();
    }
  }

  void _openRazorpayCheckout() {
    var options = {
      'key': 'rzp_test_zrejXWOWxRf29k',
      'amount': widget.totalPrice * 100,
      'timeout': 300,
      'name': 'Dup',
      'description': 'Order Payment',
      'prefill': {
        'contact': _phoneController.text,
        'email': _emailController.text
      },
      'method': {
        'upi': true,
        'card': true,
        'netbanking': true,
        'wallet': true,
      },
      'theme': {'color': '#3399cc'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      print("Payment initialization failed: ${e.toString()}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Payment initialization failed: ${e.toString()}")),
      );
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final sessionData = await Session.getSession();
      final userId = sessionData['uid'];

      final orderRef = FirebaseFirestore.instance.collection('orders').doc();
      final orderId = orderRef.id;

      final cartItemsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('cart');

      final cartItemsSnapshot = await cartItemsRef.get();
      final cartItems = cartItemsSnapshot.docs.map((doc) => doc.data()).toList();

      final productsToRemove = widget.productIds.where((productId) {
        return cartItems.any((item) => item['productId'] == productId);
      }).toList();


      List<Map<String, dynamic>> orderedProducts = [];
      for (var product in products) {
        int index = products.indexOf(product);
        orderedProducts.add({
          'productId': product['id'],
          'name': product['name'],
          'price': product['price'],
          'quantity': widget.quantities[index],
          'vendorId': product['vendorId'], // Include vendorId for each product
        });
      }

      // Get all unique vendorIds from the products
      Set<String> vendorIds = orderedProducts.map((p) => p['vendorId'] as String).toSet();

      final orderData = {
        'orderId': orderId,
        'paymentId': response.paymentId,
        'signature': response.signature,
        'amount': widget.totalPrice,
        'status': 'paid',
        'products': products.map((product) {
          int index = products.indexOf(product);
          return {
            'productId': product['id'],
            'name': product['name'],
            'price': product['price'],
            'quantity': widget.quantities[index],
          };
        }).toList(),
        'shippingAddress': {
          'name': _nameController.text,
          'address': _addressController.text,
          'city': _cityController.text,
          'state': _stateController.text,
          'zip': _zipController.text,
          'country': _countryController.text,
          'email': _emailController.text,
          'phone': _phoneController.text,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'userId': userId ?? 'guest',
        'vendorId': vendorIds.toList(),
        'matchedCartProducts': productsToRemove,
      };
      await orderRef.set(orderData);

      if (productsToRemove.isNotEmpty) {
        await _removePurchasedItemsFromCart(productsToRemove);
      }


      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Payment successful! Order ID: $orderId")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OrderConfirmationPage(orderId: orderId),
        ),
      );
    } catch (e) {
      print("Error saving order: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Payment successful but error saving order details")),
      );
    } finally {
      setState(() => isProcessingPayment = false);
    }
  }

  Future<void> _removePurchasedItemsFromCart(List<String> productsToRemove) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final cartRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('cart');

      final cartItemsSnapshot = await cartRef.get();

      final batch = FirebaseFirestore.instance.batch();
      int removedCount = 0;

      for (final doc in cartItemsSnapshot.docs) {
        final cartItem = doc.data();
        if (productsToRemove.contains(cartItem['productId'])) {
          batch.delete(doc.reference);
          removedCount++;
        }
      }

      if (removedCount > 0) {
        await batch.commit();
        print('Removed $removedCount items from cart');
      } else {
        print('No matching items found in cart');
      }

    } catch (e) {
      print('Error removing items from cart: $e');
    }
  }


  void _handlePaymentError(PaymentFailureResponse response) {
    String errorMessage = "Payment failed";

    if (response.message?.contains("network") ?? false) {
      errorMessage =
          "Network error occurred. Please check your connection and try again.";
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage)),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() => isProcessingPayment = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text("External wallet selected: ${response.walletName}")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shipping Address')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Product Summary Section
              if (isLoading)
                Center(child: CircularProgressIndicator())
              else
                Card(
                  elevation: 4,
                  margin: EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Summary',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Divider(thickness: 2),
                        ...products.map((product) {
                          int index = products.indexOf(product);
                          int quantity = widget.quantities[index];
                          return ListTile(
                            leading: product['imageUrl'] != null
                                ? Image.network(
                                    product['imageUrl'],
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  )
                                : Icon(Icons.image_not_supported),
                            title: Text(product['name']),
                            subtitle: Text(
                                'Quantity: $quantity\nPrice: ₹${product['price']}'),
                          );
                        }).toList(),
                        Divider(thickness: 2),
                        Text(
                          'Total Price: ₹${widget.totalPrice}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Shipping Address Form
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'Enter your full name',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'Enter your street address',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'City',
                  hintText: 'Enter your city',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your city';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stateController,
                decoration: const InputDecoration(
                  labelText: 'State',
                  hintText: 'Enter your state',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your state';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _zipController,
                decoration: const InputDecoration(
                  labelText: 'Zip Code',
                  hintText: 'Enter your zip code',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your zip code';
                  }
                  return null;
                },
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _countryController,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  hintText: 'Enter your country',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your country';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Enter your phone number',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  if (value.length != 10) {
                    return 'Please enter a valid 10-digit phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isProcessingPayment ? null : _submitForm,
                child: isProcessingPayment
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Save Address and Proceed to Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
