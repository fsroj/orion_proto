// main.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart'; // Para Texto a Voz
import 'package:logging/logging.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asistente Wikipedia',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: WikipediaAssistant(),
    );
  }
}

class WikipediaAssistant extends StatefulWidget {
  const WikipediaAssistant({super.key});

  @override
  WikipediaAssistantState createState() => WikipediaAssistantState();
}

class WikipediaAssistantState extends State<WikipediaAssistant> {
  final TextEditingController _searchController = TextEditingController();
  String _wikiContent = "Escribe algo para buscar en Wikipedia...";
  FlutterTts? flutterTts; // Cambia a nullable
  bool _isSpeaking = false;
  bool _isLoading = false; // Nuevo estado para indicar carga
  bool _showVolumeSlider = false;
  double _ttsVolume = 1.0;
  bool _isPaused = false;

  final Logger _logger = Logger('WikipediaAssistant');

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _logger.info("WikipediaAssistantState inicializado");
  }

  Future<void> _initializeTts() async {
    flutterTts = FlutterTts();
    await flutterTts!.setLanguage("es-ES");
    await flutterTts!.setSpeechRate(0.5);
    await flutterTts!.setVolume(_ttsVolume);
    await flutterTts!.setPitch(1.0);

    flutterTts!.setStartHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
    });

    flutterTts!.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isPaused = false;
        });
      }
    });

    flutterTts!.setErrorHandler((msg) {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isPaused = false;
        });
      }
      _logger.severe("TTS Error: $msg");
    });

    // Obtener y mostrar voces disponibles
    final voices = await flutterTts!.getVoices;
    List<Map<String, String>> parsedVoices = [];
    print("Voces disponibles:");
    for (var voice in voices) {
      if (voice is Map) {
        final voiceMap = voice.map((key, value) => MapEntry(key.toString(), value.toString()));
        parsedVoices.add(voiceMap);
        print(voiceMap); // Imprime el mapa completo
      } else {
        print(voice);
      }
    }
    // Selecciona la voz masculina si está disponible
    for (var voice in parsedVoices) {
      if (voice['name'] == 'es-es-x-eed-local' && voice['locale'] == 'es-ES') {
        await flutterTts!.setVoice(voice);
        break;
      }
    }
  }

  Future<void> _searchWikipedia(String query) async {
    if (_isSpeaking) {
      await _stopSpeaking();
    }
    if (query.isEmpty) {
      setState(() {
        _wikiContent = "Por favor, ingresa un término de búsqueda.";
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _wikiContent = "Buscando...";
    });

    final url = Uri.parse(
        'https://es.wikipedia.org/w/api.php?action=query&prop=extracts&exintro&explaintext&format=json&titles=$query');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final pages = data['query']['pages'] as Map<String, dynamic>;

        if (pages.isNotEmpty) {
          final pageId = pages.keys.first;
          if (pageId != '-1') {
            final extract = pages[pageId]['extract'];
            setState(() {
              _wikiContent = extract != null ? limpiarWikiTexto(extract) : "No se encontró contenido para '$query'.";
            });
          } else {
            setState(() {
              _wikiContent = "No se encontró '$query' en Wikipedia. Intenta con otra palabra.";
            });
          }
        } else {
          setState(() {
            _wikiContent = "No se encontró '$query' en Wikipedia. Intenta con otra palabra.";
          });
        }
      } else {
        setState(() {
          _wikiContent = "Error al conectar con Wikipedia: ${response.statusCode}. Por favor, inténtalo de nuevo.";
        });
      }
    } catch (e) {
      setState(() {
        _wikiContent = "Ocurrió un error inesperado: $e. Verifica tu conexión a internet.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _speakText(String text) async {
    final textoCorto = text.length > 500 ? text.substring(0, 500) : text;
    _logger.info("Intentando leer: [$textoCorto]");
    print("Intentando leer: [$textoCorto]");
    if (textoCorto.isNotEmpty && !_isSpeaking && flutterTts != null) {
      await flutterTts!.speak(textoCorto);
    }
  }

  Future<void> _stopSpeaking() async {
    _logger.info("Deteniendo lectura");
    if (_isSpeaking && flutterTts != null) {
      await flutterTts!.stop();
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isPaused = false;
        });
      }
    }
  }

  Future<void> _pauseSpeaking() async {
    if (flutterTts != null) {
      await flutterTts!.pause();
      setState(() {
        _isPaused = true;
      });
    }
  }

  @override
  void dispose() {
    flutterTts?.stop();
    _searchController.dispose();
    super.dispose();
  }

  String _getFaceSprite() {
    // Puedes agregar validación de existencia de asset si lo deseas
    if (_isSpeaking) {
      return 'assets/face_speaking.png';
    } else if (_isLoading) {
      return 'assets/face_thinking.png';
    } else {
      return 'assets/face_idle.png';
    }
  }

  String limpiarWikiTexto(String texto) {
    // Elimina referencias tipo [5], [n 2], etc.
    String limpio = texto.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    // Elimina caracteres invisibles y saltos de línea
    limpio = limpio.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), ' ');
    limpio = limpio.replaceAll('\n', ' ').replaceAll('\r', ' ');
    // Elimina espacios dobles
    limpio = limpio.replaceAll(RegExp(r'\s+'), ' ').trim();
    return limpio;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente de Wikipedia 📚'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Display de la cara del asistente
            AnimatedContainer(
              duration: const Duration(milliseconds: 200), // Suaviza el cambio de sprite
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  fit: BoxFit.cover,
                  image: AssetImage(
                    _getFaceSprite(), // Usa la función para obtener el sprite
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha((0.2 * 255).toInt()),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar en Wikipedia',
                hintText: 'Ej. "Albert Einstein" o "Historia de Venezuela"',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    FocusScope.of(context).unfocus(); // Ocultar teclado
                    _searchWikipedia(_searchController.text);
                  },
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                prefixIcon: const Icon(Icons.menu_book),
              ),
              onSubmitted: (value) {
                FocusScope.of(context).unfocus(); // Ocultar teclado
                _searchWikipedia(value);
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _wikiContent,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                  textAlign: TextAlign.justify,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton.icon(
                  onPressed: !_isLoading
                      ? () async {
                          if (_isSpeaking && !_isPaused) {
                            await _pauseSpeaking();
                          } else if (_isSpeaking && _isPaused) {
                            // Reproduce desde el inicio
                            setState(() {
                              _isPaused = false;
                              _isSpeaking = false;
                            });
                            await _speakText(limpiarWikiTexto(_wikiContent));
                          } else {
                            await _speakText(limpiarWikiTexto(_wikiContent));
                          }
                        }
                      : null,
                  icon: Icon(
                    _isSpeaking
                        ? (_isPaused ? Icons.play_arrow : Icons.pause)
                        : Icons.volume_up,
                  ),
                  label: Text(
                    _isSpeaking
                        ? (_isPaused ? 'Reanudar lectura' : 'Pausar lectura')
                        : 'Leer en voz alta',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _speakText("Esto es una prueba de texto a voz"),
                  child: Text("Probar TTS"),
                ),
                // Aquí podrías agregar un botón para reconocimiento de voz (requiere más configuración)
                // ElevatedButton.icon(
                //   onPressed: () { /* Lógica para reconocimiento de voz */ },
                //   icon: Icon(Icons.mic),
                //   label: Text('Dictar búsqueda'),
                // ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.settings),
                  tooltip: 'Configuración de voz',
                  onPressed: () {
                    setState(() {
                      _showVolumeSlider = !_showVolumeSlider;
                    });
                  },
                ),
              ],
            ),
            if (_showVolumeSlider)
              Row(
                children: [
                  const Icon(Icons.volume_up),
                  Expanded(
                    child: Slider(
                      value: _ttsVolume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '${(_ttsVolume * 100).toInt()}%',
                      onChanged: (value) async {
                        setState(() {
                          _ttsVolume = value;
                        });
                        if (flutterTts != null) {
                          await flutterTts!.setVolume(_ttsVolume);
                        }
                      },
                    ),
                  ),
                  Text('${(_ttsVolume * 100).toInt()}%'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}