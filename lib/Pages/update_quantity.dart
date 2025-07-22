import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ProductTestPage extends StatefulWidget {
  const ProductTestPage({super.key});

  @override
  State<ProductTestPage> createState() => _ProductTestPageState();
}

class _ProductTestPageState extends State<ProductTestPage> with SingleTickerProviderStateMixin {
  final TextEditingController _barcodeController = TextEditingController();
  String? productName;
  String? productPrice;
  String? productQuantity;
  bool isLoading = false;
  String errorMessage = '';
  bool isScanning = false;
  MobileScannerController? scannerController;

  // Animation controller for card appearance
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Track scanned barcodes to prevent duplicate processing - REMOVED for multiple scans
  DateTime? lastScanTime;
  static const Duration scanCooldown = Duration(milliseconds: 800); // Reduced cooldown

  @override
  void initState() {
    super.initState();
    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  void _initializeScanner() {
    // Dispose existing controller first
    scannerController?.dispose();

    // Create new controller with proper settings
    scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal, // Changed from noDuplicates to allow multiple scans
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    scannerController?.dispose();
    _barcodeController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<int?> _getRandAccess() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('rand_access');
  }


  Future<void> _saveCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('code', code);
  }

  Future<String?> _getCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('code');
  }

  Future<void> fetchProductByBarcode(String barcode, {bool fromScanner = false}) async {
    // Ensure barcode is treated as string and trim whitespace
    final barcodeString = barcode.toString().trim();

    if (barcodeString.isEmpty) {
      setState(() => errorMessage = 'Please enter or scan a barcode');
      return;
    }

    // Simple cooldown to prevent rapid duplicate scans
    final now = DateTime.now();
    if (lastScanTime != null && now.difference(lastScanTime!) < scanCooldown) {
      return;
    }
    lastScanTime = now;

    setState(() {
      isLoading = true;
      errorMessage = '';
      productName = null;
      productPrice = null;
      productQuantity = null;
    });

    await _saveCode(barcodeString);
    final randAccess = await _getRandAccess();
    print('rand_access value: $randAccess');

    try {
      final encodedBarcode = Uri.encodeComponent(barcodeString);
      final url = 'http://192.168.103.57/api_auth/products/by-barcode-with-quantity?barcode=$encodedBarcode&rand_access=$randAccess';

      print('Requesting URL: $url');
      print('Barcode: $barcodeString');
      print('Encoded Barcode: $encodedBarcode');
      print('rand_access: ${randAccess != null ? 'Present' : 'Missing'}');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      print('Response Status: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Parsed Data: $data');
        setState(() {
          productName = data['name']?.toString() ?? 'Unknown Product';
          productPrice = data['price']?.toString() ?? 'N/A';
          productQuantity = data['quantity']?.toString() ?? '0';
          if (fromScanner) {
            isScanning = false;
            _stopScanning();
          }
        });
        _animationController.reset();
        _animationController.forward();

        if (fromScanner) {
          _showScanFeedback(true, 'Product found!');
        }
      } else {
        print('Error Response: ${response.statusCode} - ${response.body}');
        setState(() => errorMessage = 'Product not found (${response.statusCode})');
        if (fromScanner) {
          _showScanFeedback(false, 'Product not found');
        }
      }
    } catch (e) {
      setState(() => errorMessage = 'Connection error: ${e.toString()}');
      if (fromScanner) {
        _showScanFeedback(false, 'Network error');
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showScanFeedback(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty || !isScanning) return;

    for (final barcode in barcodes) {
      // Ensure barcode value is properly converted to string
      final code = barcode.rawValue?.toString() ?? '';
      if (code.isNotEmpty) {
        // Process the first valid barcode found
        fetchProductByBarcode(code, fromScanner: true);
        break;
      }
    }
  }

  Future<void> _showQuantityDialog() async {
    final controller = TextEditingController(text: productQuantity ?? '0');
    final randAccess = await _getRandAccess();
    print('rand_access value: $randAccess');
    final code = await _getCode();

    if (randAccess == null || code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication required')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Inventory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Product: $productName'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'New Quantity',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
                ),
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.blue.shade700),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final quantity = int.tryParse(controller.text);
              if (quantity == null || quantity < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid quantity')),
                );
                return;
              }
              Navigator.pop(context);
              setState(() => isLoading = true);
              try {
                final response = await http.post(
                  Uri.parse('http://192.168.103.57/api_auth/inventory/update'),
                  headers: {
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'code': code,
                    'quantity': quantity,
                    'rand_access': randAccess,
                  }),
                );

                if (response.statusCode == 200) {
                  await fetchProductByBarcode(code);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Inventory updated successfully'),
                      backgroundColor: Colors.green.shade600,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Update failed: ${response.statusCode} - ${response.body}'),
                      backgroundColor: Colors.red.shade600,
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${e.toString()}'),
                    backgroundColor: Colors.red.shade600,
                  ),
                );
              } finally {
                setState(() => isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _toggleScanning() {
    setState(() {
      isScanning = !isScanning;
      if (isScanning) {
        _startScanning();
      } else {
        _stopScanning();
      }
    });
  }

  void _startScanning() {
    _clearAndReset();
    _initializeScanner(); // Reinitialize scanner
    // Small delay to ensure controller is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      scannerController?.start();
    });
  }

  void _stopScanning() {
    scannerController?.stop();
  }

  void _clearAndReset() {
    setState(() {
      productName = null;
      productPrice = null;
      productQuantity = null;
      errorMessage = '';
      _barcodeController.clear();
      _animationController.reset();
    });
    // Reset scan timing
    lastScanTime = null;
  }

  void _resetForNewScan() {
    // Clear previous product and reset state
    setState(() {
      productName = null;
      productPrice = null;
      productQuantity = null;
      errorMessage = '';
      isScanning = true; // Automatically start scanning mode
      _animationController.reset();
    });

    // Reset scan timing to allow immediate new scan
    lastScanTime = null;
    _barcodeController.clear();

    // Reinitialize and start scanner
    _initializeScanner();

    // Small delay to ensure controller is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      scannerController?.start();
      // Show feedback
      _showScanFeedback(true, 'Ready to scan new barcode');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Product Inventory',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue.shade800,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              isScanning ? Icons.keyboard : Icons.qr_code_scanner,
              color: Colors.white,
            ),
            onPressed: _toggleScanning,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade800,
              Colors.blue.shade50,
            ],
            stops: const [0.0, 0.3],
          ),
        ),
        child: Stack(
          children: [
            if (isScanning)
              _buildScannerView()
            else
              _buildMainView(),
          ],
        ),
      ),
      floatingActionButton: isScanning
          ? FloatingActionButton.extended(
        onPressed: _toggleScanning,
        backgroundColor: Colors.red.shade600,
        icon: const Icon(Icons.close, color: Colors.white),
        label: const Text(
          'Stop Scanning',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      )
          : null,
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        // Scanner with proper error handling
        if (scannerController != null)
          MobileScanner(
            controller: scannerController!,
            onDetect: _onBarcodeDetected,
            errorBuilder: (context, error, child) {
              return Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error,
                        color: Colors.red,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Camera Error: ${error.errorCode}',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          _initializeScanner();
                          setState(() {});
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        // Scanner overlay
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
          ),
        ),
        // Scanner frame
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.blue.shade400,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                // Corner decorations
                ...List.generate(4, (index) => _buildCornerDecoration(index)),
              ],
            ),
          ),
        ),
        // Instructions
        Positioned(
          bottom: 120,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.blue.shade400.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.center_focus_strong,
                  color: Colors.blue.shade400,
                  size: 32,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Position the barcode within the frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Scanner will automatically exit after successful scan',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCornerDecoration(int index) {
    final positions = [
      {'top': 0.0, 'left': 0.0}, // Top-left
      {'top': 0.0, 'right': 0.0}, // Top-right
      {'bottom': 0.0, 'left': 0.0}, // Bottom-left
      {'bottom': 0.0, 'right': 0.0}, // Bottom-right
    ];

    final position = positions[index];

    return Positioned(
      top: position['top'],
      left: position['left'],
      right: position['right'],
      bottom: position['bottom'],
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: index < 2 ? BorderSide(color: Colors.blue.shade400, width: 4) : BorderSide.none,
            bottom: index >= 2 ? BorderSide(color: Colors.blue.shade400, width: 4) : BorderSide.none,
            left: index % 2 == 0 ? BorderSide(color: Colors.blue.shade400, width: 4) : BorderSide.none,
            right: index % 2 == 1 ? BorderSide(color: Colors.blue.shade400, width: 4) : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildMainView() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan or enter a barcode to check product inventory',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // Search Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _barcodeController,
                      keyboardType: TextInputType.text, // Changed to text to ensure string handling
                      decoration: InputDecoration(
                        labelText: 'Enter barcode',
                        labelStyle: TextStyle(color: Colors.blue.shade700),
                        prefixIcon: Icon(Icons.qr_code, color: Colors.blue.shade700),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.search, color: Colors.blue.shade700),
                          onPressed: () => fetchProductByBarcode(_barcodeController.text),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.blue.shade200),
                        ),
                        filled: true,
                        fillColor: Colors.blue.shade50,
                      ),
                      onSubmitted: (value) => fetchProductByBarcode(value),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : () => fetchProductByBarcode(_barcodeController.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: isLoading
                            ? CircularProgressIndicator(color: Colors.white)
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search),
                            const SizedBox(width: 8),
                            const Text(
                              'SEARCH PRODUCT',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _toggleScanning,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('SCAN BARCODE'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Results Section
            if (isLoading)
              _buildLoadingWidget()
            else if (errorMessage.isNotEmpty)
              _buildErrorWidget()
            else if (productName != null)
                _buildProductCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.blue.shade700,
              ),
              const SizedBox(height: 16),
              Text(
                'Loading product information...',
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Error',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: TextStyle(
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    errorMessage = '';
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                  foregroundColor: Colors.red.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('DISMISS'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.blue.shade700,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                'Product Found',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          productName!,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Column(
            children: [
              _buildInfoRow(
                icon: Icons.attach_money,
                label: 'Price',
                value: '\$$productPrice',
              ),
              const Divider(height: 24),
              _buildInfoRow(
                icon: Icons.inventory_2,
                label: 'In Stock',
                value: productQuantity!,
                valueColor: int.tryParse(productQuantity!) != null && int.parse(productQuantity!) > 0
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
        Expanded(
        child: Container(
        height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.blue.shade600],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade700.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(

            onPressed: _showQuantityDialog,

            style: ElevatedButton.styleFrom(

              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child:FittedBox(

           child:  const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 4),
                Text(
                  'UPDATE QUANTITY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade600, Colors.green.shade500],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.green.shade600.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _resetForNewScan,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
            Icon(
            Icons.qr_code_scanner,
            color: Colors.white,
            size: 20,
          ),
          SizedBox(width: 5),
          Text(
            'SCAN AGAIN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
            ],
          ),
        ),

    ),
    ],
    ),
    ],
    ),
    ),
    ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Icon(
            icon,
            color: Colors.blue.shade700,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.blue.shade900.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.blue.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
