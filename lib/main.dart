// File: lib/main.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as mobile;
import 'package:qr/qr.dart'; 
import 'package:qr_code_tools/qr_code_tools.dart';

void main() {
  runApp(const QRSecurityApp());
}

class QRSecurityApp extends StatelessWidget {
  const QRSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Security Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: QRHomePage(),
    );
  }
}

class QRHomePage extends StatefulWidget {
  const QRHomePage({super.key});

  @override
  State<QRHomePage> createState() => _QRHomePageState();
}

class _QRHomePageState extends State<QRHomePage> {
  late Interpreter _interpreter;
  bool _isInitialized = false;
  String _result = "No prediction yet";
  File? _selectedImage;
  img.Image? _regeneratedQRImage;
  String? _qrContent;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/model.tflite');
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _result = "Error loading model: $e");
    }
  }

  /// Convert an image to the same input format as Python code
  List<List<List<List<double>>>> _preprocessImage(img.Image image) {
    // Resize to (69,69)
    final resized = img.copyResize(image, width: 69, height: 69);
    // Allocate array [1, 69, 69, 1]
    final input = List.generate(
        1,
        (_) => List.generate(
            69,
            (y) => List.generate(
                69,
                (x) => [resized.getPixel(x, y).r.toDouble() / 255.0])));
    return input;
  }


  /// Generate QR code with fixed settings (version=13, error_correction=L)
  img.Image _generateStandardQR(String content) {
    // Create the raw QR structure
    final qrCode = QrCode(13, QrErrorCorrectLevel.L)..addData(content);

    // Wrap in QrImage to get module access
    final qrImageData = QrImage(qrCode);

    final moduleCount = qrImageData.moduleCount;
    final qrImage = img.Image(width: moduleCount, height: moduleCount);
    img.fill(qrImage, color: img.ColorRgb8(255, 255, 255)); // white background

    for (int y = 0; y < moduleCount; y++) {
      for (int x = 0; x < moduleCount; x++) {
        if (qrImageData.isDark(y, x)) {
          qrImage.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }

    // Resize to 69×69 for model input
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
          _result = "Image selected. Tap 'Process QR Code' to decode and analyze.";
        });
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
          _result = "QR scanned. Tap 'Process QR Code' to regenerate and analyze.";
        });
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

    try {
      String? content;
      
      if (_selectedImage != null) {
        // Decode QR from selected image
        content = await _decodeQRFromImage(_selectedImage!);
      } else if (_qrContent != null) {
        // Use scanned QR content
        content = _qrContent;
      } else {
        setState(() => _result = "No QR code to process");
        return;
      }

      if (content == null) {
        setState(() => _result = "Could not decode QR content");
        return;
      }

      // Generate standardized QR code
      final regeneratedQR = _generateStandardQR(content);
      
      setState(() {
        _regeneratedQRImage = regeneratedQR;
      });

      // Preprocess the regenerated QR for model input
      final input = _preprocessImage(regeneratedQR);
      
      // Prepare output buffer [1,1]
      final output = List.generate(1, (_) => List.filled(1, 0.0));
      
      // Run inference
      _interpreter.run(input, output);
      
      setState(() {
        final score = output[0][0];
        final label = score >= 0.5 ? "Malicious" : "Benign";
        _result = "QR Analysis Complete!\nPrediction: $label (score: ${score.toStringAsFixed(4)})";
      });
    } catch (e) {
      setState(() => _result = "Error processing QR: $e");
    }
  }

  Future<void> _runPredictionOnAsset() async {
    if (!_isInitialized) return;
    
    try {
      // Example: load a test image from assets
      final bytes = await DefaultAssetBundle.of(context).load('assets/malicious_sample.png');
      final decoded = img.decodeImage(Uint8List.view(bytes.buffer));
      
      if (decoded == null) {
        setState(() => _result = "Could not decode asset image.");
        return;
      }

      final input = _preprocessImage(decoded);
      
      // Prepare output buffer [1,1]
      final output = List.generate(1, (_) => List.filled(1, 0.0));
      
      // Run inference
      _interpreter.run(input, output);
      
      setState(() {
        final score = output[0][0];
        final label = score >= 0.5 ? "Malicious" : "Benign";
        _result = "Asset Test - Prediction: $label (score: ${score.toStringAsFixed(4)})";
      });
    } catch (e) {
      setState(() => _result = "Error with asset prediction: $e");
    }
  }

  void _showQRSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select QR Source'),
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
      // Convert img.Image to Uint8List for display
      final png = img.encodePng(_regeneratedQRImage!);
      return Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text("Regenerated QR (69×69)", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            SizedBox(height: 4),
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
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
        title: Text('QR Security Demo'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display image or regenerated QR
            _buildQRDisplay(),
            
            if (_selectedImage != null || _regeneratedQRImage != null)
              SizedBox(height: 20),
            
            // Result text
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _result,
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            
            SizedBox(height: 30),
            
            // Buttons
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showQRSourceDialog,
                    icon: Icon(Icons.qr_code),
                    label: Text("Get QR Code"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                
                SizedBox(height: 10),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_selectedImage != null || _qrContent != null) ? _processQRCode : null,
                    icon: Icon(Icons.analytics),
                    label: Text("Process QR Code"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
                
                SizedBox(height: 20),
                
                Divider(),
                
                SizedBox(height: 10),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _runPredictionOnAsset,
                    icon: Icon(Icons.science),
                    label: Text("Test with Asset Image"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 20),
            
            // Status indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isInitialized ? Icons.check_circle : Icons.hourglass_empty,
                  color: _isInitialized ? Colors.green : Colors.orange,
                  size: 16,
                ),
                SizedBox(width: 8),
                Text(
                  _isInitialized ? "Model Ready" : "Loading Model...",
                  style: TextStyle(
                    color: _isInitialized ? Colors.green : Colors.orange,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
  }
}

// QR Scanner Page for camera scanning
class QRScannerPage extends StatefulWidget {
  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  mobile.MobileScannerController cameraController = mobile.MobileScannerController();
  bool _screenOpened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan QR Code'),
        backgroundColor: Colors.blue,
      ),
      body: mobile.MobileScanner(
        controller: cameraController,
        onDetect: (capture) {
          if (!_screenOpened) {
            final List<mobile.Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                _screenOpened = true;
                Navigator.pop(context, barcode.rawValue);
                break;
              }
            }
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}