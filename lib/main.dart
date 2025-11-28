import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WeatherApp());
}

class WeatherApp extends StatefulWidget {
  const WeatherApp({super.key});

  @override
  State<WeatherApp> createState() => _WeatherAppState();
}

class _WeatherAppState extends State<WeatherApp> {
  bool isDarkMode = false;
  bool isCelsius = true; // true = Celsius, false = Fahrenheit

  void toggleTheme() => setState(() => isDarkMode = !isDarkMode);
  void toggleUnit() => setState(() => isCelsius = !isCelsius);

  @override
  Widget build(BuildContext context) {
    final ThemeData baseTheme = isDarkMode
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData(useMaterial3: true, brightness: Brightness.light);

    return AnimatedTheme(
      data: baseTheme,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: baseTheme,
        home: WeatherHomePage(
          toggleTheme: toggleTheme,
          toggleUnit: toggleUnit,
          isDarkMode: isDarkMode,
          isCelsius: isCelsius,
        ),
      ),
    );
  }
}

class WeatherHomePage extends StatefulWidget {
  final VoidCallback toggleTheme;
  final VoidCallback toggleUnit;
  final bool isDarkMode;
  final bool isCelsius;

  const WeatherHomePage({
    super.key,
    required this.toggleTheme,
    required this.toggleUnit,
    required this.isDarkMode,
    required this.isCelsius,
  });

  @override
  State<WeatherHomePage> createState() => _WeatherHomePageState();
}

class _WeatherHomePageState extends State<WeatherHomePage> {
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic>? weatherData;
  List<dynamic> hourlyForecast = [];
  List<dynamic> dailyForecast = [];

  bool isLoading = false;
  String? lastUpdatedTime;

  static const int hourlyLimit = 6;
  static const String workerBase =
      'https://weather-proxy-worker.weatherproxy123.workers.dev';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Responsive size helper
double r(double base) {
  final width = MediaQuery.of(context).size.width;

  if (width < 400) return base * 0.9;      // Very small phones
  if (width < 600) return base * 1.0;      // Normal phones
  if (width < 900) return base * 1.15;     // Tablets
  if (width < 1400) return base * 1.28;    // Small desktops / web
  return base * 1.35;                      // Full HD / wide screens
}



  DateTime _cityTime(int ts, int offset) {
    return DateTime.fromMillisecondsSinceEpoch((ts + offset) * 1000, isUtc: true);
  }

  String _temp(dynamic v) {
    if (v == null) return "--";
    try {
      return double.parse(v.toString()).toStringAsFixed(1);
    } catch (_) {
      return "--";
    }
  }

  String _formatTemp(num tempC) {
    if (widget.isCelsius) return tempC.round().toString();
    final f = (tempC * 9 / 5) + 32;
    return f.round().toString();
  }

  String _weatherEmoji(String c) {
    final s = c.toLowerCase();
    if (s.contains("clear")) return "🌞";
    if (s.contains("cloud")) return "☁️";
    if (s.contains("rain") || s.contains("drizzle")) return "🌧️";
    if (s.contains("thunder")) return "⛈️";
    if (s.contains("snow")) return "❄️";
    if (s.contains("mist") || s.contains("fog") || s.contains("haze")) return "🌫️";
    return "🌤️";
  }

  String _dayPhase(Map<String, dynamic> w) {
    try {
      final tz = w['timezone'];
      final now = _cityTime(w['dt'], tz);
      final sr = _cityTime(w['sys']['sunrise'], tz);
      final ss = _cityTime(w['sys']['sunset'], tz);

      if (now.isBefore(sr.subtract(const Duration(minutes: 15)))) return "🌙 Night";
      if (now.isBefore(sr.add(const Duration(minutes: 30)))) return "🌅 Sunrise";
      if (now.isBefore(ss.subtract(const Duration(minutes: 30)))) return "🌞 Daytime";
      if (now.isBefore(ss)) return "🌇 Sunset";
      return "🌙 Night";
    } catch (_) {
      return "🌤️";
    }
  }

  String _formatTime(dynamic unix, dynamic tz) {
    if (unix == null) return "--";
    return DateFormat('h:mm a').format(_cityTime(unix, tz));
  }

  Color _txt(bool dark, {bool muted = false}) {
    if (dark) return muted ? Colors.white70 : Colors.white;
    return muted ? Colors.black54 : Colors.black87;
  }

  List<Color> _background(bool dark) {
    if (dark) return const [Color(0xFF061423), Color(0xFF11212B)];
    return const [Color(0xFFFFD7C2), Color(0xFFAED8FF)];
  }

  Future<void> fetchWeather(String city) async {
    if (city.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a city name.")),
      );
      return;
    }

    setState(() => isLoading = true);
    final url = Uri.parse("$workerBase?city=${Uri.encodeComponent(city)}");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        _reset("City not found. Please try again.");
        return;
      }

      final data = jsonDecode(response.body);
      if (data['error'] != null) {
        _reset("Error: ${data['error']}");
        return;
      }

      final weather = data['weather'] ?? {};
      final forecast = data['forecast'] ?? {};
      final list = forecast['list'] ?? [];

      final hourly = list.take(hourlyLimit).toList();
      final List daily = [];
      for (int i = 0; i < list.length; i += 8) {
        daily.add(list[i]);
      }

      setState(() {
        weatherData = weather;
        hourlyForecast = hourly;
        dailyForecast = daily.take(5).toList();
        lastUpdatedTime = DateFormat('hh:mm a').format(DateTime.now());
        isLoading = false;
      });
    } catch (_) {
      _reset("Network error. Please try again.");
    }
  }

  void _reset(String msg) {
    setState(() {
      weatherData = null;
      hourlyForecast = [];
      dailyForecast = [];
      isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
 
  // BUILD METHOD — Root Layout
  
  @override
  Widget build(BuildContext context) {
    final bg = _background(widget.isDarkMode);
    final titleColor = widget.isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor = _txt(widget.isDarkMode, muted: true);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: widget.toggleTheme,
        backgroundColor: widget.isDarkMode ? Colors.blueAccent : Colors.blue,
        child: Icon(
          widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
          color: Colors.white,
        ),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bg,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: r(20),
                  vertical: r(16),
                ),
                child: Column(
                  children: [
                    
                    // APP TITLE
                    
                    Column(
                      children: [
                        Text(
                          'Weather Dashboard',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: r(22),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (lastUpdatedTime != null)
                          Padding(
                            padding: EdgeInsets.only(top: r(6)),
                            child: Text(
                              'Last Updated: $lastUpdatedTime',
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: r(12),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),

                    SizedBox(height: r(10)),

                    // SEARCH BAR
                    
                    TextField(
                      controller: _searchController,
                      style: TextStyle(color: _txt(widget.isDarkMode)),
                      decoration: InputDecoration(
                        hintText: 'Search city (e.g., Chirala)',
                        hintStyle: TextStyle(
                          color: _txt(widget.isDarkMode, muted: true),
                        ),
                        filled: true,
                        fillColor: widget.isDarkMode
                            ? Colors.white.withOpacity(0.07)
                            : Colors.white.withOpacity(0.9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.search,
                              color: _txt(widget.isDarkMode)),
                          onPressed: () =>
                              fetchWeather(_searchController.text.trim()),
                        ),
                      ),
                      onSubmitted: (v) => fetchWeather(v.trim()),
                    ),

                    SizedBox(height: r(16)),
                    
                    // MAIN CONTENT
                   
                    Expanded(
                      child: isLoading
                          ? Center(
                              child: CircularProgressIndicator(
                                color: widget.isDarkMode
                                    ? Colors.white
                                    : Colors.blue,
                              ),
                            )
                          : weatherData == null
                              ? Center(
                                  child: Text(
                                    'Search for a city.🌤️',
                                    style: TextStyle(
                                      color: subtitleColor,
                                      fontSize: r(16),
                                    ),
                                  ),
                                )
                              : _buildWeatherScreen(titleColor, subtitleColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // PRIMARY WEATHER CONTENT
  
  Widget _buildWeatherScreen(Color titleColor, Color subtitleColor) {
    if (weatherData == null ||
        weatherData!['weather'] == null ||
        (weatherData!['weather'] is List &&
            weatherData!['weather'].isEmpty)) {
      return Center(
        child: Text(
          'Invalid city. Try again.',
          style: TextStyle(color: subtitleColor, fontSize: r(18)),
        ),
      );
    }

    final w = weatherData!;
    final mainEmoji = _weatherEmoji(w['weather'][0]['main']);
    final timeLabel = _dayPhase(w);

    final tempRaw = double.tryParse(_temp(w['main']?['temp'])) ?? 0.0;
    final feelsRaw = double.tryParse(_temp(w['main']?['feels_like'])) ?? 0.0;
    final humidity = w['main']?['humidity']?.toString() ?? "--";
    final wind = w['wind']?['speed']?.toString() ?? "--";

    return SingleChildScrollView(
      child: Column(
        children: [
          // MAIN CARD
          Padding(
            padding: EdgeInsets.symmetric(vertical: r(10)),
            child: _glass(
              child: Padding(
                padding: EdgeInsets.all(r(18)),
                child: Column(
                  children: [
                    // LOCATION
                    Text(
                      '${w['name']}, ${w['sys']?['country']}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: r(24),
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    SizedBox(height: r(6)),

                    // DAY PHASE
                    Text(
                      timeLabel,
                      style: TextStyle(color: subtitleColor, fontSize: r(14)),
                    ),

                    SizedBox(height: r(14)),

                    // WEATHER EMOJI
                    AnimatedWeatherEmoji(
                      emoji: mainEmoji,
                      size: (MediaQuery.of(context).size.width * 0.20)
                          .clamp(70.0, 120.0),
                      floatRange: const RangeValues(-16, 16),
                      scaleRange: const RangeValues(0.96, 1.16),
                      isLightMode: !widget.isDarkMode,
                    ),

                    SizedBox(height: r(12)),

                    // TEMPERATURE
                    Text(
                      '${_formatTemp(tempRaw)}°${widget.isCelsius ? 'C' : 'F'}',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: r(48),
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    SizedBox(height: r(8)),

                    // °C / °F SWITCH
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '°C',
                          style: TextStyle(
                            fontSize: r(14),
                            fontWeight: FontWeight.bold,
                            color:
                                widget.isCelsius ? titleColor : subtitleColor,
                          ),
                        ),
                        SizedBox(width: r(8)),
                        Transform.scale(
                          scale: 0.9,
                          child: Switch(
                            value: !widget.isCelsius,
                            onChanged: (_) => widget.toggleUnit(),
                            activeColor: Colors.blueAccent,
                          ),
                        ),
                        SizedBox(width: r(8)),
                        Text(
                          '°F',
                          style: TextStyle(
                            fontSize: r(14),
                            fontWeight: FontWeight.bold,
                            color: !widget.isCelsius
                                ? titleColor
                                : subtitleColor,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: r(12)),

                    // DESCRIPTION
                    Text(
                      w['weather'][0]['description']
                              ?.toString()
                              .toUpperCase() ??
                          "",
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: r(14),
                        letterSpacing: 1,
                      ),
                    ),

                    SizedBox(height: r(16)),

                    // QUICK STATS ROW
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _stat(LucideIcons.droplet, "Humidity", "$humidity%",
                            titleColor, subtitleColor),
                        _stat(LucideIcons.wind, "Wind", "$wind m/s", titleColor,
                            subtitleColor),
                        _stat(
                            LucideIcons.thermometer,
                            "Feels Like",
                            "${_formatTemp(feelsRaw)}°${widget.isCelsius ? 'C' : 'F'}",
                            titleColor,
                            subtitleColor),
                      ],
                    ),

                    SizedBox(height: r(12)),

                    // SUNRISE / SUNSET
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _sunStat(
                          icon: LucideIcons.sunrise,
                          label: "Sunrise",
                          value: _formatTime(
                              w['sys']?['sunrise'], w['timezone']),
                          color: subtitleColor,
                        ),
                        _sunStat(
                          icon: LucideIcons.sunset,
                          label: "Sunset",
                          value: _formatTime(
                              w['sys']?['sunset'], w['timezone']),
                          color: subtitleColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          //  HOURLY + DAILY 
          SizedBox(height: r(16)),
          if (hourlyForecast.isNotEmpty) _hourlySection(),
          SizedBox(height: r(16)),
          if (dailyForecast.isNotEmpty) _dailySection(),
        ],
      ),
    );
  }

  // GLASS CARD (used throughout UI)
 
  Widget _glass({required Widget child}) {
    if (!widget.isDarkMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.55),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: child,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.38),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: child,
    );
  }

  // SMALL TEXT + ICON STAT
  
  Widget _stat(
      IconData icon, String label, String val, Color title, Color subtitle) {
    return Column(
      children: [
        Icon(icon, size: r(20), color: subtitle),
        SizedBox(height: r(6)),
        Text(label, style: TextStyle(color: subtitle, fontSize: r(12))),
        SizedBox(height: r(6)),
        Text(
          val,
          style: TextStyle(
            color: title,
            fontSize: r(14),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // SUNRISE / SUNSET STAT
 
  Widget _sunStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: r(22), color: color),
        SizedBox(height: r(6)),
        Text(label, style: TextStyle(color: color, fontSize: r(12))),
        SizedBox(height: r(4)),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: r(13),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  
  // HOURLY FORECAST SECTION
  
  Widget _hourlySection() {
    return Column(
      children: [
        Text(
          'Hourly Forecast',
          style: TextStyle(
            color: _txt(widget.isDarkMode),
            fontSize: r(18),
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: r(10)),

        SizedBox(
          height: r(150),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double cardWidth = 110;
              const double cardSpacing = 14;

              final double totalWidth =
                  hourlyForecast.length * (cardWidth + cardSpacing);

              final bool center = constraints.maxWidth > totalWidth;

              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal:0,
                ),
                itemCount: hourlyForecast.length,
                separatorBuilder: (_, __) => SizedBox(width: r(cardSpacing)),
                itemBuilder: (context, i) {
                  final h = hourlyForecast[i];
                  final date = DateTime.tryParse(h['dt_txt'] ?? '') ??
                      DateTime.now();

                  final tempC =
                      double.tryParse(_temp(h['main']?['temp'])) ?? 0.0;
                  final icon = _weatherEmoji(h['weather'][0]['main']);

                  return _hourCard(date, tempC, icon);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // HOURLY CARD
  
  Widget _hourCard(DateTime date, double tempC, String icon) {
    final cardColor = widget.isDarkMode
        ? Colors.black.withOpacity(0.38)
        : Colors.white.withOpacity(0.8);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: widget.isDarkMode
            ? ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0)
            : ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          width: r(130),
          padding: EdgeInsets.symmetric(
            vertical: r(14),
            horizontal: r(10),
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: widget.isDarkMode
                ? null
                : Border.all(color: Colors.white.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(widget.isDarkMode ? 0.28 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('h a').format(date),
                style: TextStyle(
                  color: _txt(widget.isDarkMode),
                  fontSize: r(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: r(6)),
              Text(icon, style: TextStyle(fontSize: r(38))),
              SizedBox(height: r(8)),
              Text(
                '${_formatTemp(tempC)}°${widget.isCelsius ? 'C' : 'F'}',
                style: TextStyle(
                  color: _txt(widget.isDarkMode, muted: true),
                  fontSize: r(16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 5-DAY FORECAST SECTION
  
  Widget _dailySection() {
    return Column(
      children: [
        Text(
          '5-Day Forecast',
          style: TextStyle(
            color: _txt(widget.isDarkMode),
            fontSize: r(20),
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: r(10)),

        LayoutBuilder(
          builder: (context, constraints) {
            const double cardWidth = 110;
            const double gap = 12;

            final double totalWidth =
                dailyForecast.length * (cardWidth + gap);

            return SizedBox(
  height: r(190),
  child: LayoutBuilder(
    builder: (context, constraints) {
      const double cardWidth = 110;
      const double gap = 12;

      final double totalWidth = dailyForecast.length * (cardWidth + gap);

      final bool center = constraints.maxWidth > totalWidth;

      return ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal:
              center ? (constraints.maxWidth - totalWidth) / 2 : 6,
        ),
        itemCount: dailyForecast.length,
        itemBuilder: (_, i) {
          final d = dailyForecast[i];
          final date = DateTime.tryParse(d['dt_txt'] ?? '') ?? DateTime.now();
          final tempC = double.tryParse(_temp(d['main']?['temp'])) ?? 0.0;
          final cond = d['weather'][0]['main'];
          final emoji = _weatherEmoji(cond);

          return _dayCard(date, tempC, cond, emoji);
        },
      );
    },
  ),
);
          },
        ),
      ],
    );
  }

  // DAILY CARD
  
  Widget _dayCard(DateTime date, double tempC, String cond, String emoji) {
    final cardColor = widget.isDarkMode
        ? Colors.black.withOpacity(0.38)
        : Colors.white.withOpacity(0.75);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: widget.isDarkMode
            ? ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0)
            : ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          width: r(110),
          margin: EdgeInsets.only(right: r(12)),
          padding: EdgeInsets.all(r(12)),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: widget.isDarkMode
                ? null
                : Border.all(color: Colors.white.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(widget.isDarkMode ? 0.25 : 0.06),
                blurRadius: 7,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('E').format(date),
                style: TextStyle(
                  color: _txt(widget.isDarkMode),
                  fontWeight: FontWeight.bold,
                  fontSize: r(16),
                ),
              ),
              SizedBox(height: r(6)),
              AnimatedWeatherEmoji(
                emoji: emoji,
                size: r(40),
                floatRange: const RangeValues(-6, 6),
                scaleRange: const RangeValues(0.98, 1.10),
                isLightMode: !widget.isDarkMode,
              ),
              SizedBox(height: r(6)),
              Text(
                '${_formatTemp(tempC)}°${widget.isCelsius ? 'C' : 'F'}',
                style: TextStyle(
                  color: _txt(widget.isDarkMode),
                  fontWeight: FontWeight.bold,
                  fontSize: r(16),
                ),
              ),
              Text(
                cond,
                style: TextStyle(
                  color: _txt(widget.isDarkMode, muted: true),
                  fontSize: r(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ANIMATED WEATHER EMOJI WIDGET

class AnimatedWeatherEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  final RangeValues floatRange;
  final RangeValues scaleRange;
  final bool isLightMode;

  const AnimatedWeatherEmoji({
    super.key,
    required this.emoji,
    required this.size,
    required this.floatRange,
    required this.scaleRange,
    required this.isLightMode,
  });

  @override
  State<AnimatedWeatherEmoji> createState() => _AnimatedWeatherEmojiState();
}

class _AnimatedWeatherEmojiState extends State<AnimatedWeatherEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _float;
  late final Animation<double> _scale;
  late final Animation<double> _tilt;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _float = Tween<double>(
      begin: widget.floatRange.start,
      end: widget.floatRange.end,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    _scale = Tween<double>(
      begin: widget.scaleRange.start,
      end: widget.scaleRange.end,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    _tilt = Tween<double>(begin: -0.03, end: 0.03).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = widget.isLightMode
        ? Colors.black.withOpacity(0.10)
        : Colors.black.withOpacity(0.30);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Transform.translate(
          offset: Offset(0, _float.value),
          child: Transform.rotate(
            angle: _tilt.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: widget.size * 0.65,
                    height: widget.size * 0.65,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: glowColor,
                          blurRadius: widget.isLightMode ? 18 : 28,
                          spreadRadius: widget.isLightMode ? 2 : 4,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    widget.emoji,
                    style: TextStyle(
                      fontSize: widget.size,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 6),
                          blurRadius: widget.isLightMode ? 6 : 10,
                          color: Colors.black.withOpacity(
                              widget.isLightMode ? 0.10 : 0.32),
                        ),
                        Shadow(
                          offset: const Offset(0, 2),
                          blurRadius: 2,
                          color: Colors.black.withOpacity(0.15),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}