import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../controller/session.dart';

class ChatScreen extends StatefulWidget {
  final String otherParticipantId;
  final String displayName;

  const ChatScreen({
    Key? key,
    required this.otherParticipantId,
    required this.displayName,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  String? currentUserId;
  String? currentVendorId;
  bool _isLoading = true;
  String? _chatRoomId;

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
        currentUserId = session['uid'];
        currentVendorId = vendorSession['vid'];
        _isLoading = false;
      });

      // Initialize or find chat room after user data is loaded
      await _initializeChatRoom();
    } catch (e) {
      debugPrint("Error loading user session: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeChatRoom() async {
    if (currentUserId == null && currentVendorId == null) return;

    final myId = currentVendorId ?? currentUserId!;
    final otherId = widget.otherParticipantId;

    // Generate consistent chat room ID
    List<String> participants = [myId, otherId];
    participants.sort();
    _chatRoomId = participants.join('_');

    // Check if chat room exists, if not it will be created with first message
    setState(() {});
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _chatRoomId == null) return;

    final isVendor = currentVendorId != null;
    final senderId = isVendor ? currentVendorId! : currentUserId!;

    try {
      // Create or update chat room document
      await _firestore.collection("chat_rooms").doc(_chatRoomId).set({
        "participants": [currentVendorId ?? currentUserId, widget.otherParticipantId],
        "lastMessage": _messageController.text.trim(),
        "lastMessageTime": FieldValue.serverTimestamp(),
        "lastMessageSender": senderId,
        "lastMessageSenderType": isVendor ? "vendor" : "user",
        "unreadCount": isVendor ? 0 : FieldValue.increment(1),
      }, SetOptions(merge: true));

      // Add message to subcollection
      await _firestore
          .collection("chat_rooms")
          .doc(_chatRoomId)
          .collection("messages")
          .add({
        "senderId": senderId,
        "senderType": isVendor ? "vendor" : "user",
        "message": _messageController.text.trim(),
        "timestamp": FieldValue.serverTimestamp(),
      });

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      debugPrint("Error sending message: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send message")),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageBubble(DocumentSnapshot messageDoc) {
    final message = messageDoc.data() as Map<String, dynamic>;
    final messageText = message['message'] as String;
    final senderId = message['senderId'] as String;
    final senderType = message['senderType'] as String? ?? 'user';
    final timestamp = message['timestamp'] as Timestamp?;
    final isMe = senderId == currentUserId || senderId == currentVendorId;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.blue[100]
              : (senderType == 'vendor' ? Colors.green[100] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && senderType == 'vendor')
              Text('Vendor',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text(messageText),
            if (timestamp != null)
              Text(
                DateFormat('h:mm a').format(timestamp.toDate()),
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            "No messages yet",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            "Send your first message to start the conversation",
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName, style: TextStyle(color: Colors.white),),
        backgroundColor: Color(0xFF033015),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: _chatRoomId == null
                ? _buildEmptyState()
                : StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection("chat_rooms")
                  .doc(_chatRoomId)
                  .collection("messages")
                  .orderBy("timestamp", descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return _buildEmptyState();
                }

                if (snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    return _buildMessageBubble(snapshot.data!.docs[index]);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0, left: 8.0, bottom: 50),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}