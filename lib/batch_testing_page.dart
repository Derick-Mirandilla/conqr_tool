// File: lib/batch_testing_page.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class BatchTestingPage extends StatefulWidget {
  const BatchTestingPage({super.key});

  @override
  State<BatchTestingPage> createState() => _BatchTestingPageState();
}

class _BatchTestingPageState extends State<BatchTestingPage> {
  late Interpreter _interpreter;
  bool _isInitialized = false;
  bool _isTesting = false;
  
  List<File> _benignImages = [];
  List<File> _maliciousImages = [];
  
  // Metrics
  double? _accuracy;
  double? _precision;
  double? _recall;
  double? _f1Score;
  double? _auc;
  int? _tp, _tn, _fp, _fn;
  int _processedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/model_weighted.tflite');
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint("Error loading model: $e");
    }
  }

  Future<void> _pickBenignImages() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'],
        dialogTitle: 'Select Benign Images',
        withData: false, // Don't load file data into memory
        withReadStream: false,
      );

      if (result != null && result.files.isNotEmpty) {
        List<File> newImages = [];
        for (var file in result.files) {
          if (file.path != null) {
            newImages.add(File(file.path!));
          }
        }
        
        setState(() {
          _benignImages.addAll(newImages);
        });
        
        _showSnackBar(
          'Added ${newImages.length} benign image${newImages.length != 1 ? 's' : ''}',
          Colors.green,
        );
      } else {
        _showSnackBar('No images selected', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Error picking benign images: $e', Colors.red);
      debugPrint('Error picking benign images: $e');
    }
  }

  Future<void> _pickMaliciousImages() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'],
        dialogTitle: 'Select Malicious Images',
        withData: false,
        withReadStream: false,
      );

      if (result != null && result.files.isNotEmpty) {
        List<File> newImages = [];
        for (var file in result.files) {
          if (file.path != null) {
            newImages.add(File(file.path!));
          }
        }
        
        setState(() {
          _maliciousImages.addAll(newImages);
        });
        
        _showSnackBar(
          'Added ${newImages.length} malicious image${newImages.length != 1 ? 's' : ''}',
          Colors.red,
        );
      } else {
        _showSnackBar('No images selected', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Error picking malicious images: $e', Colors.red);
      debugPrint('Error picking malicious images: $e');
    }
  }



  List<List<List<List<double>>>> _preprocessImage(img.Image image) {
    
    final input = List.generate(1, (_) => 
      List.generate(69, (y) => 
        List.generate(69, (x) {
          final pixel = image.getPixel(x, y);
          // Get the grayscale value and normalize
          final grayValue = pixel.r.toDouble() / 255.0;
          return [grayValue];
        })
      )
    );
    
    // Debug: Print sample values
    final sampleValues = input[0][34].take(5).map((col) => col[0].toStringAsFixed(4)).join(", ");
    debugPrint('DEBUG - Sample values at row 34: $sampleValues');
    
    return input;
  }

  Future<void> _runBatchTesting() async {
    if (!_isInitialized) {
      _showSnackBar('Model not initialized', Colors.red);
      return;
    }

    if (_benignImages.isEmpty && _maliciousImages.isEmpty) {
      _showSnackBar('Please select images for testing', Colors.orange);
      return;
    }

    setState(() {
      _isTesting = true;
      _processedCount = 0;
      _totalCount = _benignImages.length + _maliciousImages.length;
    });

    try {
      List<int> yTrue = [];
      List<int> yPred = [];
      List<double> yProbs = [];

      // Debug: Track probability distributions
      List<double> benignProbs = [];
      List<double> maliciousProbs = [];

      // Process benign images (label = 0)
      for (var imageFile in _benignImages) {
        try {
          final bytes = await imageFile.readAsBytes();
          final image = img.decodeImage(bytes);
          
          if (image == null) {
            debugPrint('Failed to decode image: ${imageFile.path}');
            continue;
          }
          
          // Don't use img.grayscale() - convert manually during preprocessing
          final input = _preprocessImage(image);
          final output = List.generate(1, (_) => List.filled(1, 0.0));
          _interpreter.run(input, output);
          
          final prob = output[0][0];
          yTrue.add(0);
          yProbs.add(prob);
          yPred.add(prob >= 0.5 ? 1 : 0);
          benignProbs.add(prob);
          
          setState(() => _processedCount++);
        } catch (e) {
          debugPrint('Error processing benign image ${imageFile.path}: $e');
        }
      }

      // Process malicious images (label = 1)
      for (var imageFile in _maliciousImages) {
        try {
          final bytes = await imageFile.readAsBytes();
          final image = img.decodeImage(bytes);
          
          if (image == null) {
            debugPrint('Failed to decode image: ${imageFile.path}');
            continue;
          }
          

          final input = _preprocessImage(image);
          final output = List.generate(1, (_) => List.filled(1, 0.0));
          _interpreter.run(input, output);
          
          final prob = output[0][0];
          yTrue.add(1);
          yProbs.add(prob);
          yPred.add(prob >= 0.5 ? 1 : 0);
          maliciousProbs.add(prob);
          
          setState(() => _processedCount++);
        } catch (e) {
          debugPrint('Error processing malicious image ${imageFile.path}: $e');
        }
      }

      // Debug output
      if (benignProbs.isNotEmpty) {
        debugPrint('=== BENIGN IMAGE PREDICTIONS ===');
        debugPrint('Count: ${benignProbs.length}');
        debugPrint('Min prob: ${benignProbs.reduce((a, b) => a < b ? a : b)}');
        debugPrint('Max prob: ${benignProbs.reduce((a, b) => a > b ? a : b)}');
        debugPrint('Avg prob: ${benignProbs.reduce((a, b) => a + b) / benignProbs.length}');
        debugPrint('Sample probs: ${benignProbs.take(10).join(", ")}');
      }
      
      if (maliciousProbs.isNotEmpty) {
        debugPrint('=== MALICIOUS IMAGE PREDICTIONS ===');
        debugPrint('Count: ${maliciousProbs.length}');
        debugPrint('Min prob: ${maliciousProbs.reduce((a, b) => a < b ? a : b)}');
        debugPrint('Max prob: ${maliciousProbs.reduce((a, b) => a > b ? a : b)}');
        debugPrint('Avg prob: ${maliciousProbs.reduce((a, b) => a + b) / maliciousProbs.length}');
        debugPrint('Sample probs: ${maliciousProbs.take(10).join(", ")}');
      }

      // Calculate metrics
      if (yTrue.isNotEmpty) {
        _calculateMetrics(yTrue, yPred, yProbs);
        _showSnackBar('Testing completed successfully!', Colors.green);
      } else {
        _showSnackBar('No images were successfully processed', Colors.red);
      }

    } catch (e) {
      _showSnackBar('Error during testing: $e', Colors.red);
      debugPrint('Error during testing: $e');
    } finally {
      setState(() => _isTesting = false);
    }
  }

  void _calculateMetrics(List<int> yTrue, List<int> yPred, List<double> yProbs) {
    if (yTrue.isEmpty) return;

    // Confusion matrix
    int tp = 0, tn = 0, fp = 0, fn = 0;
    for (int i = 0; i < yTrue.length; i++) {
      if (yTrue[i] == 1 && yPred[i] == 1) tp++;
      else if (yTrue[i] == 0 && yPred[i] == 0) tn++;
      else if (yTrue[i] == 0 && yPred[i] == 1) fp++;
      else if (yTrue[i] == 1 && yPred[i] == 0) fn++;
    }

    // Basic metrics
    final accuracy = (tp + tn) / yTrue.length;
    final precision = tp + fp > 0 ? tp / (tp + fp) : 0.0;
    final recall = tp + fn > 0 ? tp / (tp + fn) : 0.0;
    final f1 = precision + recall > 0 ? 2 * (precision * recall) / (precision + recall) : 0.0;

    // AUC calculation
    final auc = _calculateAUC(yTrue, yProbs);

    setState(() {
      _accuracy = accuracy;
      _precision = precision;
      _recall = recall;
      _f1Score = f1;
      _auc = auc;
      _tp = tp;
      _tn = tn;
      _fp = fp;
      _fn = fn;
    });
  }

  double _calculateAUC(List<int> yTrue, List<double> yProbs) {
    List<MapEntry<double, int>> combined = [];
    for (int i = 0; i < yTrue.length; i++) {
      combined.add(MapEntry(yProbs[i], yTrue[i]));
    }
    combined.sort((a, b) => b.key.compareTo(a.key));

    double auc = 0.0;
    int posCount = yTrue.where((y) => y == 1).length;
    int negCount = yTrue.length - posCount;
    
    if (posCount == 0 || negCount == 0) return 0.5;

    int tpCount = 0;
    int fpCount = 0;
    double prevTPR = 0.0;
    double prevFPR = 0.0;

    for (var entry in combined) {
      if (entry.value == 1) {
        tpCount++;
      } else {
        fpCount++;
      }
      
      double tpr = tpCount / posCount;
      double fpr = fpCount / negCount;
      
      auc += (fpr - prevFPR) * (tpr + prevTPR) / 2.0;
      
      prevTPR = tpr;
      prevFPR = fpr;
    }

    return auc;
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearAll() {
    setState(() {
      _benignImages.clear();
      _maliciousImages.clear();
      _accuracy = null;
      _precision = null;
      _recall = null;
      _f1Score = null;
      _auc = null;
      _tp = null;
      _tn = null;
      _fp = null;
      _fn = null;
      _processedCount = 0;
      _totalCount = 0;
    });
    _showSnackBar('All data cleared', Colors.grey);
  }

  void _showSelectionOptions(bool isBenign) {
    if (isBenign) {
      _pickBenignImages();
    } else {
      _pickMaliciousImages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Testing', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFFF8A00),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_benignImages.isNotEmpty || _maliciousImages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearAll,
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF292727),
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                         MediaQuery.of(context).padding.top - 
                         kToolbarHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Model Status
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3838),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isInitialized ? Icons.check_circle : Icons.hourglass_empty,
                      color: _isInitialized ? const Color(0xFFFF8A00) : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isInitialized ? 'Model Ready' : 'Loading Model...',
                      style: TextStyle(
                        color: _isInitialized ? const Color(0xFFFF8A00) : Colors.orange,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // Image Selection Section
              _buildSectionTitle('1. Select Test Images'),
              const SizedBox(height: 12),
              
              _buildImageSelector(
                'Benign Images',
                _benignImages.length,
                Colors.green,
                () => _showSelectionOptions(true),
              ),
              
              const SizedBox(height: 12),
              
              _buildImageSelector(
                'Malicious Images',
                _maliciousImages.length,
                Colors.red,
                () => _showSelectionOptions(false),
              ),

              const SizedBox(height: 24),

              // Run Test Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: (_isInitialized && !_isTesting && 
                            (_benignImages.isNotEmpty || _maliciousImages.isNotEmpty))
                      ? _runBatchTesting
                      : null,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.play_arrow, color: Colors.white),
                  label: Text(
                    _isTesting 
                        ? 'Testing... $_processedCount/$_totalCount'
                        : 'Run Batch Test',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Results Section
              if (_accuracy != null) ...[
                _buildSectionTitle('2. Test Results'),
                const SizedBox(height: 12),
                
                _buildMetricsCard('Performance Metrics', [
                  _buildMetricRow('Accuracy', _accuracy!, Colors.blue),
                  _buildMetricRow('Precision', _precision!, Colors.purple),
                  _buildMetricRow('Recall', _recall!, Colors.orange),
                  _buildMetricRow('F1-Score', _f1Score!, Colors.green),
                  _buildMetricRow('AUC', _auc!, Colors.teal),
                ]),

                const SizedBox(height: 12),

                _buildMetricsCard('Confusion Matrix', [
                  _buildCountRow('True Positives (TP)', _tp!, Colors.green),
                  _buildCountRow('True Negatives (TN)', _tn!, Colors.blue),
                  _buildCountRow('False Positives (FP)', _fp!, Colors.orange),
                  _buildCountRow('False Negatives (FN)', _fn!, Colors.red),
                ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildImageSelector(String label, int count, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3A3838),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.folder_open, color: color),
        ),
        title: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '$count image${count != 1 ? 's' : ''} selected',
          style: TextStyle(color: Colors.grey[400]),
        ),
        trailing: const Icon(Icons.add, color: Color(0xFFFF8A00)),
        onTap: onTap,
      ),
    );
  }

  Widget _buildMetricsCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3838),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFF8A00),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value.toStringAsFixed(4),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
  }
}