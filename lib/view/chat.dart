import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controller/session.dart';
import 'messagescreen.dart';

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? currentUserId; // Changed from late to nullable
  String? currentVendorId;
  final Map<String, Map<String, dynamic>> _userCache = {};
  bool _isLoading = true; // Added loading state

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final session = await Session.getSession();
      final vendorSession = await Session.getVendor();

      setState(() {
        currentUserId = session['uid'] ?? _auth.currentUser?.uid;
        currentVendorId = vendorSession['vid'];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading user session: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (currentUserId == null && currentVendorId == null) {
      return Center(child: Text("User not authenticated"));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chats", style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF033015),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection("chat_rooms")
            .where("participants", arrayContainsAny: _getParticipantIds())
            .orderBy("lastMessageTime", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error loading chats"));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text("No chats available"));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final chatRoom = snapshot.data!.docs[index];
              return _buildChatListItem(chatRoom);
            },
          );
        },
      ),
    );
  }

  List<String> _getParticipantIds() {
    final ids = <String>[];
    if (currentUserId != null && currentUserId!.isNotEmpty) {
      ids.add(currentUserId!);
    }
    if (currentVendorId != null && currentVendorId!.isNotEmpty) {
      ids.add(currentVendorId!);
    }
    return ids;
  }

  Widget _buildChatListItem(QueryDocumentSnapshot chatRoom) {
    try {
      final participants = List<String>.from(chatRoom["participants"] ?? []);

      // Get the other participant ID
      final otherUserId = participants.firstWhere(
            (id) => id != currentUserId && id != currentVendorId,
        orElse: () => "",
      );

      if (otherUserId.isEmpty) return SizedBox.shrink();

      return FutureBuilder<Map<String, dynamic>>(
        future: _getParticipantData(otherUserId),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return ListTile(
              leading: CircleAvatar(child: CircularProgressIndicator()),
              title: Text("Loading..."),
            );
          }

          if (userSnapshot.hasError || !userSnapshot.hasData) {
            return ListTile(
              title: Text("Unknown chat"),
              subtitle: Text("Could not load participant info"),
            );
          }

          final userData = userSnapshot.data ?? {};
          final displayName = userData["businessName"] ??
              userData["name"] ??
              "Unknown";
          final isOtherUserVendor = userData["businessName"] != null;
          final profileImage = userData["profileImage"];

          // Safely access chat room fields
          final lastMessage = chatRoom["lastMessage"]?.toString() ?? "No messages yet";
          final lastMessageTime = chatRoom["lastMessageTime"] as Timestamp?;
          final lastMessageSender = chatRoom["lastMessageSender"]?.toString() ?? "";
          dynamic unreadCount = chatRoom["unreadCount"];

          // Determine if current user sent the last message
          final isCurrentUserSender =
              (currentUserId != null && lastMessageSender == currentUserId) ||
                  (currentVendorId != null && lastMessageSender == currentVendorId);

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: profileImage != null
                    ? NetworkImage(profileImage)
                    : null,
                child: profileImage == null && displayName.isNotEmpty
                    ? Text(displayName[0])
                    : null,
              ),
              title: Text(displayName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOtherUserVendor ? "Business" : "User",
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (lastMessageTime != null)
                    Text(
                      DateFormat('h:mm a').format(lastMessageTime.toDate()),
                      style: TextStyle(fontSize: 12),
                    ),
                  if (!isCurrentUserSender && unreadCount > 0)
                    Container(
                      margin: EdgeInsets.only(top: 4),
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount.toString(),
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      otherParticipantId: otherUserId,
                      displayName: displayName,
                    ),
                  ),
                ).then((_) {
                  if (!isCurrentUserSender) {
                    _firestore.collection("chat_rooms").doc(chatRoom.id).update({
                      "unreadCount": 0,
                    });
                  }
                });
              },
            ),
          );
        },
      );
    } catch (e) {
      debugPrint("Error building chat item: $e");
      return ListTile(
        title: Text("Invalid chat"),
        subtitle: Text("Could not load chat information"),
      );
    }
  }

  Future<Map<String, dynamic>> _getParticipantData(String userId) async {
    if (_userCache.containsKey(userId)) return _userCache[userId]!;

    try {
      // First check vendors collection
      final vendorDoc = await _firestore.collection("vendors").doc(userId).get();
      if (vendorDoc.exists) {
        _userCache[userId] = vendorDoc.data()!;
        return vendorDoc.data()!;
      }

      // If not found in vendors, check users collection
      final userDoc = await _firestore.collection("users").doc(userId).get();
      if (userDoc.exists) {
        _userCache[userId] = userDoc.data()!;
        return userDoc.data()!;
      }
    } catch (e) {
      debugPrint("Error fetching participant data: $e");
    }

    return {};
  }
}