import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class StockChartScreen extends StatefulWidget {
  const StockChartScreen({super.key, required this.symbol});

  final String symbol;

  @override
  State<StockChartScreen> createState() => _StockChartScreenState();
}

class _StockChartScreenState extends State<StockChartScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(
        Uri.parse(
          "https://www.tradingview.com/chart/?symbol=${_toTvSymbol(widget.symbol)}",
        ),
      );

    //
    // _controller = WebViewController()
    //   ..setJavaScriptMode(JavaScriptMode.unrestricted)
    //   ..setNavigationDelegate(
    //     NavigationDelegate(
    //       onPageFinished: (_) => setState(() => _loading = false),
    //     ),
    //   )
    //   ..loadHtmlString(_buildHtml(widget.symbol));
  }

//   String _buildHtml(String symbol) {
//     return '''
// <!DOCTYPE html>
// <html>
// <head>
//   <meta name="viewport" content="width=device-width, initial-scale=1.0">
//
//   <style>
//     html, body {
//       margin: 0;
//       padding: 0;
//       height: 100%;
//       width: 100%;
//       background: #ffffff;
//     }
//
//     .tradingview-widget-container {
//       height: 100%;
//       width: 100%;
//     }
//
//     #tradingview_chart {
//       height: 100%;
//       width: 100%;
//     }
//   </style>
// </head>
//
// <body>
//
// <div class="tradingview-widget-container">
//   <div id="tradingview_chart"></div>
//
//   <script src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js">
//   {
//     "width": "100%",
//     "height": "100%",
//     "symbol": symbol,
//     "interval": "D",
//     "timezone": "Asia/Kolkata",
//     "theme": "light",
//     "style": "1",
//     "locale": "en",
//     "allow_symbol_change": true
//   }
//   </script>
// </div>
//
// </body>
// </html>
// ''';
//   }

  /// Convert a raw price-server symbol to a TradingView exchange:symbol string.
  static String _toTvSymbol(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'NIFTY':     return 'NSE:NIFTY50';
      case 'BANKNIFTY': return 'NSE:BANKNIFTY';
      case 'SENSEX':    return 'BSE:SENSEX';
      case 'GOLD':      return 'MCX:GOLD1!';
      case 'CRUDEOIL':  return 'MCX:CRUDEOIL1!';
      case 'USDINR':    return 'FX_IDC:USDINR';
      default:          return 'NSE:${symbol.toUpperCase()}';
    }
  }

  String _buildHtml(String symbol) {
    final tvSymbol = _toTvSymbol(symbol);

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <style>
    html, body {
      margin: 0;
      padding: 0;
      height: 100%;
      width: 100%;
      background: #ffffff;
    }

    #tv_chart {
      width: 100%;
      height: 100%;
    }
  </style>
</head>

<body>

<div id="tv_chart"></div>

<script src="https://s3.tradingview.com/tv.js"></script>

<script>
  new TradingView.widget({
    "container_id": "tv_chart",
    "width": "100%",
    "height": "100%",
    "symbol": "$tvSymbol", // ✅ FIXED (DART → JS)
    "interval": "D",
    "timezone": "Asia/Kolkata",
    "theme": "light",
    "style": "1",
    "locale": "en",
    "toolbar_bg": "#f1f5f9",
    "enable_publishing": false,
    "hide_top_toolbar": false,
    "hide_legend": false
  });
</script>

</body>
</html>
''';
  }
//   String _buildHtml(String symbol) {
//     return '''
// <!DOCTYPE html>
// <html>
// <head>
//   <meta name="viewport" content="width=device-width, initial-scale=1.0">
//   <style>
//     body {
//       margin: 0;
//       background: #ffffff;
//     }
//   </style>
// </head>
//
// <body>
//
// <div class="tradingview-widget-container">
//   <div id="tradingview_chart"></div>
//
//   <script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js">
//   {
//     "width": "100%",
//     "height": "100%",
//     "symbol": symbol,
//     "interval": "D",
//     "timezone": "Asia/Kolkata",
//     "theme": "light",
//     "style": "1",
//     "locale": "en",
//     "allow_symbol_change": true,
//     "hide_side_toolbar": false,
//     "hide_top_toolbar": false
//   }
//   </script>
// </div>
//
// </body>
// </html>
// ''';
//   }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Column(
          children: [

            /// 🔥 CUSTOM HEADER (WITH BACK BUTTON)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14,vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [

                  /// 🔙 BACK BUTTON
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: Colors.black,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // / 📊 ICON
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFF1F5F9),
                    child: Icon(Icons.show_chart, color: Colors.black),
                  ),


                  const SizedBox(width: 12),

                  /// 🧠 TEXT
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.symbol.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Live Chart View",
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),


                  Spacer(),
                  Image.asset("assets/images/small_logo.png",height: 40,),
                ],
              ),
            ),

            /// 📊 CHART AREA
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: WebViewWidget(controller: _controller),
                  ),

                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF4C46E5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}