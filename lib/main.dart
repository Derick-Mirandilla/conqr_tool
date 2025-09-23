// File: lib/main.dart
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as mobile;
import 'package:qr/qr.dart'; 
import 'package:qr_code_tools/qr_code_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const QRSecurityApp());
}

class QRSecurityApp extends StatelessWidget {
  const QRSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Security Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const LandingPage(),
      routes: {
        '/main': (context) => const MainAppPage(),
        '/about': (context) => const AboutPage(),
        '/history': (context) => const HistoryPage(),
        '/contact': (context) => const ContactPage(),
      },
    );
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Color(0xFF292727)
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo Section
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/logo.png', 
                      width: 400,
                      height: 240,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
              
              // Buttons Section
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/main');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF8A00),
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/about');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFD9D9D9),
                            foregroundColor: Color(0xFF292727),
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Text(
                            'About Us',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// History Data Model - Fixed JSON handling
class QRAnalysisHistory {
  final String id;
  final String fileName;
  final String imagePath;
  final DateTime timestamp;
  final String result;
  final double confidence;
  final String? content;

  QRAnalysisHistory({
    required this.id,
    required this.fileName,
    required this.imagePath,
    required this.timestamp,
    required this.result,
    required this.confidence,
    this.content,
  });

  // Fixed JSON serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'imagePath': imagePath,
    'timestamp': timestamp.toIso8601String(),
    'result': result,
    'confidence': confidence,
    'content': content,
  };

  // Fixed JSON deserialization with error handling
  factory QRAnalysisHistory.fromJson(Map<String, dynamic> json) {
    try {
      return QRAnalysisHistory(
        id: json['id']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? 'Unknown',
        imagePath: json['imagePath']?.toString() ?? '',
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
        result: json['result']?.toString() ?? 'Unknown',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        content: json['content']?.toString(),
      );
    } catch (e) {
      debugPrint('Error parsing QRAnalysisHistory: $e');
      return QRAnalysisHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fileName: 'Corrupted Entry',
        imagePath: '',
        timestamp: DateTime.now(),
        result: 'Error',
        confidence: 0.0,
        content: null,
      );
    }
  }
}

// Main App Page 
class MainAppPage extends StatefulWidget {
  const MainAppPage({super.key});

  @override
  State<MainAppPage> createState() => _MainAppPageState();
}

class _MainAppPageState extends State<MainAppPage> {
  late Interpreter _interpreter;
  bool _isInitialized = false;
  String _result = "No analysis yet";
  File? _selectedImage;
  img.Image? _regeneratedQRImage;
  String? _qrContent;
  String? _decodedContent;
  String? _analysisResult;
  double? _analysisConfidence;
  final ImagePicker _picker = ImagePicker();
  List<QRAnalysisHistory> _history = [];
  bool _isAnalyzing = false;
  bool _showContent = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadHistory();
  }

  // Fixed history loading with proper JSON handling
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJsonList = prefs.getStringList('qr_history') ?? [];
      
      setState(() {
        _history = historyJsonList.map((jsonString) {
          try {
            final Map<String, dynamic> jsonMap = json.decode(jsonString);
            return QRAnalysisHistory.fromJson(jsonMap);
          } catch (e) {
            debugPrint('Error decoding history item: $e');
            return null;
          }
        }).where((item) => item != null).cast<QRAnalysisHistory>().toList();
      });
      
      debugPrint('Loaded ${_history.length} history items');
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() {
        _history = [];
      });
    }
  }

  // Fixed history saving with proper JSON handling
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJsonList = _history.map((item) {
        try {
          return json.encode(item.toJson());
        } catch (e) {
          debugPrint('Error encoding history item: $e');
          return null;
        }
      }).where((item) => item != null).cast<String>().toList();
      
      await prefs.setStringList('qr_history', historyJsonList);
      debugPrint('Saved ${historyJsonList.length} history items');
    } catch (e) {
      debugPrint('Error saving history: $e');
    }
  }

  Future<void> _addToHistory(String fileName, String imagePath, String result, double confidence, String? content) async {
    try {
      final history = QRAnalysisHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fileName: fileName,
        imagePath: imagePath,
        timestamp: DateTime.now(),
        result: result,
        confidence: confidence,
        content: content,
      );
      
      setState(() {
        _history.insert(0, history);
        if (_history.length > 50) { // Keep only last 50 records
          _history = _history.take(50).toList();
        }
      });
      
      await _saveHistory();
      debugPrint('Added new history item: $fileName - $result');
    } catch (e) {
      debugPrint('Error adding to history: $e');
    }
  }



  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/model.tflite');
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _result = "Error loading model: $e");
    }
  }

  List<List<List<List<double>>>> _preprocessImage(img.Image image) {
    final resized = img.copyResize(image, width: 69, height: 69);
    final input = List.generate(
        1,
        (_) => List.generate(
            69,
            (y) => List.generate(
                69,
                (x) => [resized.getPixel(x, y).r.toDouble() / 255.0])));
    return input;
  }

  img.Image _generateStandardQR(String content) {
    final qrCode = QrCode(13, QrErrorCorrectLevel.L)..addData(content);
    final qrImageData = QrImage(qrCode);

    final moduleCount = qrImageData.moduleCount;
    final qrImage = img.Image(width: moduleCount, height: moduleCount);
    img.fill(qrImage, color: img.ColorRgb8(255, 255, 255));

    for (int y = 0; y < moduleCount; y++) {
      for (int x = 0; x < moduleCount; x++) {
        if (qrImageData.isDark(y, x)) {
          qrImage.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }

    return img.copyResize(qrImage, width: 69, height: 69);
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _regeneratedQRImage = null;
          _qrContent = null;
          _result = "Image selected. Processing automatically...";
          _isAnalyzing = true;
        });
        
        // Auto-analyze after selection
        await _processQRCode();
      }
    } catch (e) {
      setState(() => _result = "Error picking image: $e");
    }
  }

  Future<void> _scanQRFromCamera() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => QRScannerPage()),
      );
      
      if (result != null) {
        setState(() {
          _qrContent = result;
          _selectedImage = null;
          _result = "QR scanned. Processing automatically...";
          _isAnalyzing = true;
        });
        
        // Auto-analyze after scanning
        await _processQRCode();
      }
    } catch (e) {
      setState(() => _result = "Error scanning QR: $e");
    }
  }

  Future<String?> _decodeQRFromImage(File imageFile) async {
    try {
      final String? content = await QrCodeToolsPlugin.decodeFrom(imageFile.path);
      return content;
    } catch (e) {
      debugPrint("QR decode error: $e");
      return null;
    }
  }

  Future<void> _processQRCode() async {
    if (!_isInitialized) {
      setState(() => _result = "Model not initialized yet");
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      String? content;
      
      if (_selectedImage != null) {
        content = await _decodeQRFromImage(_selectedImage!);
      } else if (_qrContent != null) {
        content = _qrContent;
      } else {
        setState(() => _result = "No QR code to process");
        return;
      }

      if (content == null) {
        setState(() {
          _result = "Could not decode QR content";
          _isAnalyzing = false;
        });
        return;
      }

      final regeneratedQR = _generateStandardQR(content);
      
      setState(() {
        _regeneratedQRImage = regeneratedQR;
      });

      final input = _preprocessImage(regeneratedQR);
      final output = List.generate(1, (_) => List.filled(1, 0.0));
      
      _interpreter.run(input, output);
      
      final score = output[0][0];
      final label = score >= 0.35 ? "Malicious" : "Benign";
      
      // Store the decoded content and analysis results for potential opening
      _decodedContent = content;
      _analysisResult = label;
      _analysisConfidence = score;
      
      // Add to history
      await _addToHistory(
        _selectedImage?.path.split('/').last ?? 'Scanned QR',
        _selectedImage?.path ?? '',
        label,
        score,
        content,
      );
      
      setState(() {
        _result = "Analysis Complete!\nResult: $label\nConfidence: ${(score * 100).toStringAsFixed(1)}%";
        _isAnalyzing = false;
        _showContent = false; // Hide content by default
      });

      // Show post-analysis dialog
      _showPostAnalysisDialog(label, score, content);
    } catch (e) {
      setState(() {
        _result = "Error processing QR: $e";
        _isAnalyzing = false;
      });
    }
  }

  void _showPostAnalysisDialog(String result, double confidence, String content) {
    final isMalicious = result == "Malicious";
    final confidencePercentage = (confidence * 100).toStringAsFixed(1);
    
    showDialog(
      context: context,
      barrierDismissible: false, // Force user to make a choice
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isMalicious ? Icons.warning : Icons.check_circle,
                    color: isMalicious ? Colors.red.shade600 : Colors.green.shade600,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isMalicious ? 'Security Warning!' : 'Analysis Complete',
                      style: TextStyle(
                        color: isMalicious ? Colors.red.shade700 : Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Analysis Result
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMalicious ? Colors.red.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isMalicious ? Colors.red.shade200 : Colors.green.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Analysis Result: $result',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isMalicious ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Confidence: $confidencePercentage%',
                            style: TextStyle(
                              color: isMalicious ? Colors.red.shade600 : Colors.green.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Warning message for malicious QRs
                    if (isMalicious) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.orange.shade600, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Security Risks:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '• May redirect to phishing websites\n'
                              '• Could download malware\n'
                              '• May steal personal information\n'
                              '• Could perform unauthorized actions',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange.shade700,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // QR Content section with privacy toggle
                    Row(
                      children: [
                        Text(
                          'QR Code Content:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              _showContent = !_showContent;
                            });
                          },
                          child: Text(
                            _showContent ? 'Hide Content' : 'Reveal Content',
                            style: TextStyle(
                              color: Color(0xFFFF8A00),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _showContent 
                        ? SelectableText(
                            content,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          )
                        : Row(
                            children: [
                              Icon(Icons.visibility_off, 
                                   color: Colors.grey.shade500, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Content hidden for privacy',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Action question
                    if (_showContent)
                      Text(
                        _isUrlContent(content) 
                          ? (isMalicious 
                              ? '⚠️ Do you really want to open this potentially dangerous link?'
                              : '🔗 Would you like to open this link?')
                          : (isMalicious 
                              ? '⚠️ This QR contains potentially malicious content.'
                              : '✅ This QR appears to be safe.'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isMalicious ? Colors.red.shade700 : Color(0xFFFF8A00),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                // Cancel/Close button
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                
                // Copy content button (only if content is shown)
                if (_showContent)
                  TextButton(
                    onPressed: () {
                      _copyToClipboard(content);
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Copy Content',
                      style: TextStyle(color: Color(0xFFFF8A00)),
                    ),
                  ),
                
                // Open link button (only for URLs and if content is shown)
                if (_showContent && _isUrlContent(content)) ...[
                  if (isMalicious) ...[
                    // Extra warning for malicious URLs
                    TextButton(
                      onPressed: () => _showFinalWarningDialog(content),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        backgroundColor: Colors.red.shade50,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning, size: 16),
                          SizedBox(width: 4),
                          Text('Open Anyway'),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Safe to open
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _launchUrl(content);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 16),
                          SizedBox(width: 4),
                          Text('Open Link'),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }

  void _showFinalWarningDialog(String content) {
    Navigator.of(context).pop(); // Close previous dialog
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.dangerous, color: Colors.red.shade600, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Final Warning!',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      '🚨 DANGER ZONE 🚨',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Our AI has detected this QR code as MALICIOUS with high confidence. '
                      'Opening this link could:\n\n'
                      '• Compromise your device security\n'
                      '• Steal your personal data\n'
                      '• Install malware\n'
                      '• Perform financial fraud\n\n'
                      'Are you absolutely sure you want to proceed?',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Keep Me Safe'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _launchUrl(content);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade600,
              ),
              child: const Text('Open at My Own Risk'),
            ),
          ],
        );
      },
    );
  }

  bool _isUrlContent(String content) {
    return content.toLowerCase().startsWith('http://') || 
           content.toLowerCase().startsWith('https://') ||
           content.toLowerCase().startsWith('www.');
  }

  Future<void> _launchUrl(String url) async {
    try {
      // Clean and validate the URL
      String cleanUrl = url.trim();
      
      // Add protocol if missing
      if (!cleanUrl.toLowerCase().startsWith('http://') && 
          !cleanUrl.toLowerCase().startsWith('https://')) {
        if (cleanUrl.toLowerCase().startsWith('www.')) {
          cleanUrl = 'https://$cleanUrl';
        } else if (cleanUrl.contains('.') && !cleanUrl.contains(' ')) {
          // Assume it's a domain without www
          cleanUrl = 'https://$cleanUrl';
        } else {
          throw Exception('Invalid URL format');
        }
      }
      
      final Uri uri = Uri.parse(cleanUrl);
      
      // Validate the URI
      if (uri.scheme.isEmpty || uri.host.isEmpty) {
        throw Exception('Invalid URL format');
      }
      
      bool launched = false;
      
      // Try different launch modes
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        // If external application fails, try platformDefault
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
        } catch (e2) {
          // If that fails too, try inAppWebView as last resort
          launched = await launchUrl(
            uri,
            mode: LaunchMode.inAppWebView,
          );
        }
      }
      
      if (!launched) {
        throw Exception('Could not launch URL');
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open URL: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            action: SnackBarAction(
              label: 'Copy URL',
              textColor: Colors.white,
              onPressed: () => _copyToClipboard(url),
            ),
          ),
        );
      }
    }
  }

  Future<void> _copyToClipboard(String content) async {
    try {
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Content copied to clipboard'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Upload QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan with Camera'),
                subtitle: const Text('Real-time QR scanning'),
                onTap: () {
                  Navigator.pop(context);
                  _scanQRFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Select from Gallery'),
                subtitle: const Text('Choose QR image from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQRDisplay() {
    if (_regeneratedQRImage != null) {
      final png = img.encodePng(_regeneratedQRImage!);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              "Processed QR Code",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Image.memory(
              Uint8List.fromList(png),
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
          ],
        ),
      );
    } else if (_selectedImage != null) {
      return Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            _selectedImage!,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container();
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Image.asset(
            'assets/images/logo.png',
            height: 70,
            fit: BoxFit.contain,
          )
        ],
      ),
      backgroundColor: Color(0xFFFF8A00),
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
    ),
    drawer: Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF3A3838),
              Color(0xFF2A2828),
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF8A00),
                    Color(0xFFE67700),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.qr_code_scanner,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'QR Code Analyzer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Smart Analysis Tool',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.history,
              title: 'History',
              route: '/history',
              description: 'View past scans',
            ),
            _buildDrawerItem(
              context,
              icon: Icons.info_outline,
              title: 'About',
              route: '/about',
              description: 'Learn more about the app',
            ),
            _buildDrawerItem(
              context,
              icon: Icons.contact_support,
              title: 'Contact',
              route: '/contact',
              description: 'Get in touch with us',
            ),
          ],
        ),
      ),
    ),
    body: Container(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Display section
            if (_selectedImage != null || _regeneratedQRImage != null) ...[
              _buildQRDisplay(),
              const SizedBox(height: 20),
            ],
            
            // Analysis indicator
            if (_isAnalyzing) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFFF8A00)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFF8A00)),
                    const SizedBox(height: 16),
                    Text(
                      'Analyzing QR Code...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Result display
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade200,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.analytics,
                    size: 32,
                    color: Color(0xFFFF8A00),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _result,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Upload button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _showUploadDialog,
                icon: const Icon(Icons.upload, color: Colors.white),
                label: const Text(
                  'Upload QR Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFF8A00),
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),

            // Review Analysis button (only show if there's a completed analysis)
            if (_decodedContent != null && _analysisResult != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _showPostAnalysisDialog(
                    _analysisResult!, 
                    _analysisConfidence!, 
                    _decodedContent!
                  ),
                  icon: Icon(Icons.info_outline, color: Color(0xFFFF8A00)),
                  label: Text(
                    'Review Analysis Results',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF8A00),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Color(0xFFFF8A00), width: 2),
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 30),
            
            // Status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isInitialized 
                  ? Color(0xFFFF8A00).withOpacity(0.1) 
                  : Colors.orange.shade600.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isInitialized ? Color(0xFFFF8A00) : Colors.orange.shade600,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isInitialized ? Icons.check_circle : Icons.hourglass_empty,
                    color: _isInitialized ? Color(0xFFFF8A00) : Colors.orange.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isInitialized ? "Model Ready" : "Loading Model...",
                    style: TextStyle(
                      color: _isInitialized ? Color(0xFFFF8A00) : Colors.orange.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildDrawerItem(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String route,
  required String description,
}) {
  return Container(
    margin: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: Color(0xFFFF8A00),
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          color: Colors.white.withOpacity(0.7),
          fontSize: 12,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onTap: () {
        Navigator.pop(context); // Close the drawer
        Navigator.pushNamed(context, route);
      },
      hoverColor: Colors.white.withOpacity(0.1),
      splashColor: Color(0xFFFF8A00).withOpacity(0.3),
    ),
  );
}

  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
  }
}

// History Page
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<QRAnalysisHistory> _history = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterBy = 'all'; // all, malicious, benign

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      setState(() => _isLoading = true);
      
      final prefs = await SharedPreferences.getInstance();
      final historyJsonList = prefs.getStringList('qr_history') ?? [];
      
      setState(() {
        _history = historyJsonList.map((jsonString) {
          try {
            final Map<String, dynamic> jsonMap = json.decode(jsonString);
            return QRAnalysisHistory.fromJson(jsonMap);
          } catch (e) {
            debugPrint('Error decoding history item: $e');
            return null;
          }
        }).where((item) => item != null).cast<QRAnalysisHistory>().toList();
        
        _isLoading = false;
      });
      
      debugPrint('Loaded ${_history.length} history items');
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() {
        _history = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF3A3838),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear History', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete all analysis history? This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('qr_history');
        setState(() {
          _history.clear();
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('History cleared successfully'),
              backgroundColor: Color(0xFFFF8A00),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing history: $e'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteHistoryItem(QRAnalysisHistory item) async {
    try {
      setState(() {
        _history.removeWhere((h) => h.id == item.id);
      });
      
      final prefs = await SharedPreferences.getInstance();
      final historyJsonList = _history.map((item) => json.encode(item.toJson())).toList();
      await prefs.setStringList('qr_history', historyJsonList);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Item deleted from history'),
            backgroundColor: Color(0xFFFF8A00),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _history.add(item);
                  _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                });
                prefs.setStringList('qr_history', 
                  _history.map((item) => json.encode(item.toJson())).toList());
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting item: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _showHistoryDetails(QRAnalysisHistory item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF3A3838),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              item.result == "Malicious" ? Icons.warning : Icons.check_circle,
              color: item.result == "Malicious" ? Colors.red.shade600 : Color(0xFFFF8A00),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Analysis Details', style: TextStyle(color: Colors.white))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('File Name', item.fileName),
              _buildDetailRow('Result', item.result),
              _buildDetailRow('Confidence', '${(item.confidence * 100).toStringAsFixed(1)}%'),
              _buildDetailRow('Date', '${item.timestamp.day}/${item.timestamp.month}/${item.timestamp.year}'),
              _buildDetailRow('Time', '${item.timestamp.hour}:${item.timestamp.minute.toString().padLeft(2, '0')}'),
              if (item.content != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'QR Content:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF292727),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[600]!),
                  ),
                  child: SelectableText(
                    item.content!,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.grey[400])),
          ),
          if (item.content != null)
            ElevatedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: item.content!));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Content copied to clipboard'),
                    backgroundColor: Color(0xFFFF8A00),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF8A00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Copy Content', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[400]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<QRAnalysisHistory> get _filteredHistory {
    var filtered = _history;
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) =>
        item.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (item.content?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }
    
    // Apply result filter
    if (_filterBy != 'all') {
      filtered = filtered.where((item) =>
        item.result.toLowerCase() == _filterBy.toLowerCase()
      ).toList();
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _filteredHistory;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis History', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFFFF8A00),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Color(0xFF3A3838),
            onSelected: (value) {
              if (value == 'clear') {
                _clearHistory();
              } else if (value == 'refresh') {
                _loadHistory();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Color(0xFFFF8A00)),
                    SizedBox(width: 8),
                    Text('Refresh', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear All', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Color(0xFF292727),
        ),
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF8A00),
                ),
              )
            : Column(
                children: [
                  // Search and Filter Section
                  if (_history.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Search Bar
                          TextField(
                            style: TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Search history...',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              prefixIcon: Icon(Icons.search, color: Color(0xFFFF8A00)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[600]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[600]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Color(0xFFFF8A00), width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              filled: true,
                              fillColor: Color(0xFF3A3838),
                            ),
                            onChanged: (value) => setState(() => _searchQuery = value),
                          ),
                          const SizedBox(height: 12),
                          
                          // Filter Chips
                          Row(
                            children: [
                              Text('Filter: ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: const Text('All'),
                                labelStyle: TextStyle(
                                  color: _filterBy == 'all' ? Colors.white : Colors.grey[400],
                                ),
                                selected: _filterBy == 'all',
                                selectedColor: Color(0xFFFF8A00),
                                backgroundColor: Color(0xFF3A3838),
                                onSelected: (selected) => setState(() => _filterBy = 'all'),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: const Text('Malicious'),
                                labelStyle: TextStyle(
                                  color: _filterBy == 'malicious' ? Colors.white : Colors.grey[400],
                                ),
                                selected: _filterBy == 'malicious',
                                selectedColor: Colors.red.shade600,
                                backgroundColor: Color(0xFF3A3838),
                                onSelected: (selected) => setState(() => _filterBy = 'malicious'),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: const Text('Benign'),
                                labelStyle: TextStyle(
                                  color: _filterBy == 'benign' ? Colors.white : Colors.grey[400],
                                ),
                                selected: _filterBy == 'benign',
                                selectedColor: Colors.green.shade600,
                                backgroundColor: Color(0xFF3A3838),
                                onSelected: (selected) => setState(() => _filterBy = 'benign'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  // History List
                  Expanded(
                    child: filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _history.isEmpty ? Icons.history : Icons.search_off,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _history.isEmpty 
                                    ? 'No analysis history yet'
                                    : 'No results found',
                                  style: TextStyle(fontSize: 18, color: Colors.grey[400]),
                                ),
                                if (_history.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Start analyzing QR codes to see your history here',
                                    style: TextStyle(color: Colors.grey[400]),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Color(0xFF3A3838),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: item.result == "Malicious" 
                                        ? Colors.red.shade600.withOpacity(0.1) 
                                        : Colors.green.shade600.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      item.result == "Malicious" ? Icons.warning : Icons.check_circle,
                                      color: item.result == "Malicious" ? Colors.red.shade600 : Colors.green.shade600,
                                      size: 32,
                                    ),
                                  ),
                                  title: Text(
                                    item.fileName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: item.result == "Malicious" 
                                                ? Colors.red.shade600 
                                                : Colors.green.shade600,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              item.result,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${(item.confidence * 100).toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              color: Colors.grey[300],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.timestamp.day}/${item.timestamp.month}/${item.timestamp.year} '
                                        '${item.timestamp.hour}:${item.timestamp.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    color: Color(0xFF3A3838),
                                    onSelected: (value) {
                                      if (value == 'details') {
                                        _showHistoryDetails(item);
                                      } else if (value == 'delete') {
                                        _deleteHistoryItem(item);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'details',
                                        child: Row(
                                          children: [
                                            Icon(Icons.info_outline, color: Color(0xFFFF8A00)),
                                            SizedBox(width: 8),
                                            Text('View Details', style: TextStyle(color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _showHistoryDetails(item),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

// About Page
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Us', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFFFF8A00),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Color(0xFF292727),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 150,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Mission Section
              Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Color(0xFF3A3838),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Our Mission',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We provide advanced security analysis for QR codes using cutting-edge machine learning technology. Our goal is to protect users from malicious QR codes that could compromise their security and privacy.',
                      style: TextStyle(
                        fontSize: 16, 
                        height: 1.5,
                        color: Colors.grey[300],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Features Section
              Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Color(0xFF3A3838),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Features',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildFeatureItem(Icons.security, 'AI-Powered Analysis', 'Advanced machine learning models detect malicious patterns'),
                    _buildFeatureItem(Icons.speed, 'Real-time Processing', 'Instant analysis results with confidence scores'),
                    _buildFeatureItem(Icons.history, 'Analysis History', 'Track and review your previous QR code scans'),
                    _buildFeatureItem(Icons.camera_alt, 'Multiple Input Methods', 'Scan with camera or upload from gallery'),
                  ],
                ),
              ),
              
              // Technology Section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Color(0xFF3A3838),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Technology',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Built using TensorFlow Lite for efficient on-device machine learning inference, ensuring your data stays private and secure.',
                      style: TextStyle(
                        fontSize: 16, 
                        height: 1.5,
                        color: Colors.grey[300],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFFF8A00).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon, 
              color: Color(0xFFFF8A00), 
              size: 24
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[400],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Contact Page
class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFFFF8A00),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
         width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Color(0xFF292727),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Get in Touch',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We\'d love to hear from you. Send us a message and we\'ll respond as soon as possible.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[300],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              
              _buildContactItem(
                Icons.email,
                'Email',
                'support@yourapp.com',
                'Send us an email',
              ),
              
              _buildContactItem(
                Icons.phone,
                'Phone',
                '+1 (555) 123-4567',
                'Call us during business hours',
              ),
              
              _buildContactItem(
                Icons.location_on,
                'Address',
                '123 Tech Street\nTech City, TC 12345',
                'Visit our office',
              ),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String title, String content, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF3A3838),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFFFF8A00).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Color(0xFFFF8A00),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFFF8A00),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// QR Scanner Page (enhanced with better UI)
class QRScannerPage extends StatefulWidget {
  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  mobile.MobileScannerController cameraController = mobile.MobileScannerController();
  bool _screenOpened = false;
  bool _isFlashOn = false;
  bool _isFrontCamera = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFFFF8A00),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Flash toggle
          IconButton(
            onPressed: () async {
              await cameraController.toggleTorch();
              setState(() {
                _isFlashOn = !_isFlashOn;
              });
            },
            icon: Icon(
              _isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
          ),
          // Camera switch
          IconButton(
            onPressed: () async {
              await cameraController.switchCamera();
              setState(() {
                _isFrontCamera = !_isFrontCamera;
              });
            },
            icon: const Icon(
              Icons.switch_camera,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera view
          mobile.MobileScanner(
            controller: cameraController,
            onDetect: (capture) {
              if (!_screenOpened) {
                final List<mobile.Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _screenOpened = true;
                    
                    // Show success feedback
                    HapticFeedback.lightImpact();
                    
                    // Return the scanned content
                    Navigator.pop(context, barcode.rawValue);
                    break;
                  }
                }
              }
            },
          ),
          
          // Scanning overlay
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: Colors.white,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 5,
                cutOutSize: MediaQuery.of(context).size.width * 0.7,
              ),
            ),
          ),
          
          // Instructions overlay
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Position the QR code within the frame',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The QR code will be scanned automatically',
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          
          // Status indicators
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_isFlashOn)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.yellow.shade600,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flash_on, color: Colors.black, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Flash On',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (_isFrontCamera)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color(0xFFFF8A00),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_front, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Front Camera',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}

// QR Scanner Overlay Shape
class QrScannerOverlayShape extends ShapeBorder {
  const QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    double? cutOutSize,
  }) : cutOutSize = cutOutSize ?? 250;

  final Color overlayColor;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path _getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top + borderRadius)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + borderRadius, rect.top)
        ..lineTo(rect.right, rect.top);
    }

    return _getLeftTopPath(rect)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final _cutOutSize = cutOutSize < width && cutOutSize < height 
        ? cutOutSize 
        : (width < height ? width : height) - borderOffset * 2;
    final _cutOutRadius = borderRadius + borderOffset;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - _cutOutSize / 2 + borderOffset,
      rect.top + height / 2 - _cutOutSize / 2 + borderOffset,
      _cutOutSize - borderOffset * 2,
      _cutOutSize - borderOffset * 2,
    );

    final cutOutRRect = RRect.fromRectAndRadius(
      cutOutRect,
      Radius.circular(_cutOutRadius),
    );

    final overlayPaint = Paint()
      ..color = overlayColor;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    // Fixed: Create the overlay with a hole in the middle
    final overlayPath = Path()
      ..addRect(rect)  // Add the full rectangle
      ..addRRect(cutOutRRect)  // Add the cutout area
      ..fillType = PathFillType.evenOdd;  // This creates the hole

    // Draw the overlay with the hole
    canvas.drawPath(overlayPath, overlayPaint);

    // Draw border corners
    final cornerRadius = _cutOutRadius;
    final cornerPath = Path();

    // Top Left
    cornerPath.moveTo(cutOutRect.left - borderOffset, cutOutRect.top + cornerRadius);
    cornerPath.quadraticBezierTo(
      cutOutRect.left - borderOffset, 
      cutOutRect.top - borderOffset, 
      cutOutRect.left + cornerRadius, 
      cutOutRect.top - borderOffset
    );
    cornerPath.lineTo(cutOutRect.left + borderLength, cutOutRect.top - borderOffset);

    cornerPath.moveTo(cutOutRect.left - borderOffset, cutOutRect.top + borderLength);
    cornerPath.lineTo(cutOutRect.left - borderOffset, cutOutRect.top + cornerRadius);

    // Top Right
    cornerPath.moveTo(cutOutRect.right + borderOffset, cutOutRect.top + cornerRadius);
    cornerPath.quadraticBezierTo(
      cutOutRect.right + borderOffset, 
      cutOutRect.top - borderOffset, 
      cutOutRect.right - cornerRadius, 
      cutOutRect.top - borderOffset
    );
    cornerPath.lineTo(cutOutRect.right - borderLength, cutOutRect.top - borderOffset);

    cornerPath.moveTo(cutOutRect.right + borderOffset, cutOutRect.top + borderLength);
    cornerPath.lineTo(cutOutRect.right + borderOffset, cutOutRect.top + cornerRadius);

    // Bottom Left
    cornerPath.moveTo(cutOutRect.left - borderOffset, cutOutRect.bottom - cornerRadius);
    cornerPath.quadraticBezierTo(
      cutOutRect.left - borderOffset, 
      cutOutRect.bottom + borderOffset, 
      cutOutRect.left + cornerRadius, 
      cutOutRect.bottom + borderOffset
    );
    cornerPath.lineTo(cutOutRect.left + borderLength, cutOutRect.bottom + borderOffset);

    cornerPath.moveTo(cutOutRect.left - borderOffset, cutOutRect.bottom - borderLength);
    cornerPath.lineTo(cutOutRect.left - borderOffset, cutOutRect.bottom - cornerRadius);

    // Bottom Right
    cornerPath.moveTo(cutOutRect.right + borderOffset, cutOutRect.bottom - cornerRadius);
    cornerPath.quadraticBezierTo(
      cutOutRect.right + borderOffset, 
      cutOutRect.bottom + borderOffset, 
      cutOutRect.right - cornerRadius, 
      cutOutRect.bottom + borderOffset
    );
    cornerPath.lineTo(cutOutRect.right - borderLength, cutOutRect.bottom + borderOffset);

    cornerPath.moveTo(cutOutRect.right + borderOffset, cutOutRect.bottom - borderLength);
    cornerPath.lineTo(cutOutRect.right + borderOffset, cutOutRect.bottom - cornerRadius);

    canvas.drawPath(cornerPath, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      overlayColor: overlayColor,
    );
  }
}