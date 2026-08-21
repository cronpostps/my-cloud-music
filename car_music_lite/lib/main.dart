// lib/main.dart v1.3

// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart'; 

const String baseUrl = 'https://mm.cronpost.com'; 
String globalCookie = ''; 

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CarMusicLiteApp());
}

class CarMusicLiteApp extends StatelessWidget {
  const CarMusicLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Music Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
        ),
      ),
      home: const LoginScreen(), 
    );
  }
}

// ==========================================
// MÀN HÌNH ĐĂNG NHẬP
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkSavedPin(); 
  }

  Future<void> _checkSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('saved_pin');
    
    if (savedPin != null && savedPin.isNotEmpty) {
      _pinController.text = savedPin;
      _login(); 
    }
  }

  Future<void> _login() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'pin': pin}),
      );

      if (response.statusCode == 200) {
        final rawCookie = response.headers['set-cookie'];
        if (rawCookie != null) {
          int index = rawCookie.indexOf(';');
          if (index == -1) {
            globalCookie = rawCookie;
          } else {
            globalCookie = rawCookie.substring(0, index);
          }
        }
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_pin', pin);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MusicPlayerScreen()),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Mã PIN không đúng';
        });
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('saved_pin') == pin) {
         if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MusicPlayerScreen()),
            );
         }
      } else {
        setState(() {
          _errorMessage = 'Mất mạng! Không thể xác thực.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🔒 Bảo Mật', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Vui lòng nhập mã PIN', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 5),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF282828),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 10),
              if (_errorMessage.isNotEmpty)
                Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('MỞ KHÓA', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class MyHttpAudioSource extends StreamAudioSource {
  final String url;
  final String cookie;

  MyHttpAudioSource(this.url, this.cookie);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    final req = http.Request('GET', Uri.parse(url));
    req.headers['Cookie'] = cookie;
    
    bool hasEnd = end != null;
    req.headers['Range'] = 'bytes=$start-${hasEnd ? end : ''}';

    final response = await req.send();
    if (response.statusCode >= 400) {
      throw Exception('HTTP Error: ${response.statusCode}');
    }

    int? totalLength;
    final contentRange = response.headers['content-range'];
    if (contentRange != null) {
      final parts = contentRange.split('/');
      if (parts.length == 2) {
        totalLength = int.tryParse(parts[1]);
      }
    } else {
      totalLength = response.contentLength;
    }

    return StreamAudioResponse(
      sourceLength: totalLength,
      contentLength: response.contentLength,
      offset: start,
      stream: response.stream,
      contentType: response.headers['content-type'] ?? 'audio/mpeg',
    );
  }
}

// ==========================================
// MÀN HÌNH PHÁT NHẠC
// ==========================================
class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _mainFocusNode = FocusNode();

  static const _platform = MethodChannel('car_music_lite/native_keys');
  
  List<dynamic> _allSongs = [];     
  List<dynamic> _displaySongs = []; 
  List<String> _folders = [];       
  Set<String> _downloadedSongIds = {}; 
  final Set<String> _downloadingIds = {}; 

  String _currentFolder = 'all';
  
  Map<String, dynamic>? _currentSong; 
  int _currentIndex = -1;
  
  bool _isLoading = true;

  double _currentSpeed = 1.0;       
  bool _isShuffle = false; 
  int _loopMode = 0; 
  bool _playFromStart = false;
  bool _skipMode = false;
  int _skipStart = 5;
  int _skipEnd = 10;

  // BIẾN QUẢN LÝ SLIDER THỜI GIAN
  bool _isSeeking = false;
  double _dragValue = 0.0;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _progressTimer; 

  bool _isDownloadingAll = false;
  int _downloadAllTotal = 0;
  int _downloadAllProgress = 0;

  @override
  void initState() {
    super.initState();
    _initData();

    HardwareKeyboard.instance.addHandler(_handleSteeringWheelKeys);

    _platform.setMethodCallHandler((call) async {
      if (call.method == "next") {
        _playNext();
      } else if (call.method == "prev") {
        _playPrev();
      } else if (call.method == "toggle") {
        _togglePlayPause();
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestFocus();
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_currentSong != null) {
           _addTrendScore(_currentSong!['id']);
        }
        if (_loopMode == 2) {
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.play();
        } else {
          _playNext();
        }
      }
    });

    _audioPlayer.positionStream.listen((position) {
      final duration = _audioPlayer.duration;
      if (_skipMode && duration != null && _audioPlayer.playing) {
        if (duration.inSeconds > 0 && position.inSeconds >= duration.inSeconds - _skipEnd) {
           if (_loopMode == 2) {
             _audioPlayer.seek(Duration(seconds: _skipStart > 0 && _skipMode ? _skipStart : 0));
           } else {
             _playNext();
           }
        }
      }
    });

    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_audioPlayer.playing && _currentSong != null) {
        _currentSong!['current_time'] = _audioPlayer.position.inSeconds; 
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_folder', _currentFolder);
        await prefs.setString('last_song_id', _currentSong!['id']);
        await prefs.setInt('last_current_time', _audioPlayer.position.inSeconds);

        try {
          await http.post(
            Uri.parse('$baseUrl/api/progress'),
            headers: {'Content-Type': 'application/json', 'Cookie': globalCookie},
            body: json.encode({
              'songId': _currentSong!['id'],
              'currentTime': _audioPlayer.position.inSeconds,
              'folder': _currentFolder
            })
          );
        } catch (e) {
          // Bỏ qua nếu lỗi mạng
        }
      }
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    HardwareKeyboard.instance.removeHandler(_handleSteeringWheelKeys);
    _progressTimer?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _requestFocus() {
    if (mounted && !_mainFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_mainFocusNode);
    }
  }

  bool _handleSteeringWheelKeys(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.mediaTrackNext) {
        _playNext();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious) {
        _playPrev();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
        _togglePlayPause();
        return true;
      }
    }
    return false;
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '00:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final hours = duration.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  // HÀM MỚI: Bắn thông tin bài hát sang Native Android
  Future<void> _updateNativeMetadata(String title, String artist) async {
    try {
      await _platform.invokeMethod('updateMetadata', {
        'title': title,
        'artist': artist,
      });
    } on PlatformException catch (e) {
      debugPrint("Lỗi gửi metadata: ${e.message}");
    }
  }

  void _recalculateCurrentIndex() {
    if (_currentSong != null) {
      _currentIndex = _displaySongs.indexWhere((s) => s['id'] == _currentSong!['id']);
    } else {
      _currentIndex = -1;
    }
  }

  Future<void> _initData() async {
    await _loadSettings(); 
    await _checkDownloadedFiles();
    await _fetchSongs();
    await _restoreLastSession();
  }

  Future<void> _restoreLastSession() async {
    String targetFolder = 'all';
    String targetSongId = '';
    int targetTime = 0;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/last-session'),
        headers: {'Cookie': globalCookie}
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        final data = json.decode(response.body);
        targetFolder = data['context_path'] ?? 'all';
        targetSongId = data['song_id'] ?? '';
        targetTime = data['current_time'] ?? 0;
      } else {
        throw Exception('No online session data');
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      targetFolder = prefs.getString('last_folder') ?? 'offline_only';
      targetSongId = prefs.getString('last_song_id') ?? '';
      targetTime = prefs.getInt('last_current_time') ?? 0;
      
      if (targetFolder == 'offline_only' && targetSongId.isEmpty && _downloadedSongIds.isNotEmpty) {
        targetSongId = _downloadedSongIds.first;
      }
    }

    if (targetFolder != 'all') {
      _applyFolderFilter(targetFolder);
    }

    if (targetSongId.isNotEmpty) {
      int index = _displaySongs.indexWhere((s) => s['id'] == targetSongId);
      if (index != -1) {
        _displaySongs[index]['current_time'] = targetTime; 
        await _playSong(index, autoPlay: false);
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/settings'),
        headers: {'Cookie': globalCookie}
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _playFromStart = data['play_from_start'] == 1;
          _skipMode = data['skip_mode'] == 1;
          _skipStart = data['skip_start'] ?? 5;
          _skipEnd = data['skip_end'] ?? 10;
          _isShuffle = data['shuffle_mode'] == 1;
          _loopMode = data['repeat_mode'] ?? 0;
          _currentSpeed = (data['playback_rate'] ?? 1.0).toDouble();
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải cài đặt: $e");
    }
  }

  Future<void> _saveSettings() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/settings'),
        headers: {'Content-Type': 'application/json', 'Cookie': globalCookie},
        body: json.encode({
          'playFromStart': _playFromStart,
          'skipMode': _skipMode,
          'skipStart': _skipStart,
          'skipEnd': _skipEnd,
          'isShuffle': _isShuffle,
          'loopMode': _loopMode,
          'playbackRate': _currentSpeed
        })
      );
    } catch (e) {
      debugPrint("Lỗi lưu cài đặt: $e");
    }
  }

  Future<void> _checkDownloadedFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync();
      Set<String> ids = {};
      for (var file in files) {
        if (file.path.endsWith('.mp3')) {
          ids.add(file.path.split(Platform.pathSeparator).last.replaceAll('.mp3', ''));
        }
      }
      setState(() {
        _downloadedSongIds = ids;
      });
    } catch (e) {
      debugPrint("Lỗi kiểm tra file: $e");
    }
  }

  Future<void> _fetchSongs() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/songs'),
        headers: {'Cookie': globalCookie}, 
      ).timeout(const Duration(seconds: 10)); 
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await prefs.setString('cached_songs', json.encode(data['data']));
        setState(() {
          _allSongs = data['data']; 
          _displaySongs = List.from(_allSongs);
          _extractFolders(); 
          _recalculateCurrentIndex(); 
          _isLoading = false;
        });
      } else {
        throw Exception('Lỗi API');
      }
    } catch (e) {
      final cachedStr = prefs.getString('cached_songs');
      if (cachedStr != null) {
        setState(() {
          _allSongs = json.decode(cachedStr);
          _displaySongs = List.from(_allSongs);
          _extractFolders();
          _recalculateCurrentIndex(); 
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Chạy Offline'), backgroundColor: Color(0xFF282828))
          );
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchSpecialList(String endpoint, String folderName) async {
    setState(() { 
      _isLoading = true; 
      _currentFolder = folderName; 
    });
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'), 
        headers: {'Cookie': globalCookie}
      ).timeout(const Duration(seconds: 5)); 
      
      if (response.statusCode == 200) {
        setState(() { 
          _displaySongs = json.decode(response.body); 
          _recalculateCurrentIndex(); 
          _isLoading = false; 
        });
      } else {
        throw Exception('Lỗi lấy danh sách đặc biệt');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Cần mạng!'))
        );
      }
    }
  }

  void _extractFolders() {
    Set<String> folderSet = {};
    for (var song in _allSongs) {
      folderSet.add((song['folder_path'] ?? 'Root').toString().trim());
    }
    _folders = folderSet.toList()..sort();
  }

  void _searchSongs(String query) {
    if (query.isEmpty) {
      _applyFolderFilter(_currentFolder);
      return;
    }
    setState(() {
      _displaySongs = _allSongs.where((s) => (s['name'] ?? '').toString().toLowerCase().contains(query.toLowerCase())).toList();
      _recalculateCurrentIndex(); 
    });
  }

  void _applyFolderFilter(String folder) {
    setState(() {
      _currentFolder = folder;
      if (folder == 'all') {
        _displaySongs = List.from(_allSongs);
      } else if (folder == 'favorites') {
        _displaySongs = _allSongs.where((s) => s['is_favorite'] == 1).toList();
      } else if (folder == 'offline_only') {
        _displaySongs = _allSongs.where((s) => _downloadedSongIds.contains(s['id'])).toList();
      } else {
        _displaySongs = _allSongs.where((s) => (s['folder_path'] ?? 'Root').toString().trim() == folder).toList();
      }
      _recalculateCurrentIndex(); 
    });
  }

  Future<void> _toggleFavorite(String songId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/favorite/toggle'), 
        headers: {'Content-Type': 'application/json', 'Cookie': globalCookie}, 
        body: json.encode({'songId': songId})
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          for (var s in _allSongs) {
            if (s['id'] == songId) {
              s['is_favorite'] = data['is_favorite'];
            }
          }
          for (var s in _displaySongs) {
            if (s['id'] == songId) {
              s['is_favorite'] = data['is_favorite'];
            }
          }
          if (_currentSong != null && _currentSong!['id'] == songId) {
             _currentSong!['is_favorite'] = data['is_favorite'];
          }

          if (_currentFolder == 'favorites' && data['is_favorite'] == 0) {
            _displaySongs.removeWhere((s) => s['id'] == songId);
            _recalculateCurrentIndex(); 
          }
        });
      }
    } catch (e) {
      debugPrint('Lỗi thả tim: $e');
    }
  }

  Future<void> _addTrendScore(String songId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/trend/add'), 
        headers: {'Content-Type': 'application/json', 'Cookie': globalCookie}, 
        body: json.encode({'songId': songId})
      );
    } catch (e) {
      debugPrint('Lỗi ghi nhận điểm: $e');
    }
  }

  Future<void> _toggleDownload(String songId) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$songId.mp3');

    if (_downloadedSongIds.contains(songId)) {
      if (!mounted) {
        return;
      }
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Xóa file Offline?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('HỦY', style: TextStyle(color: Colors.grey))
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                if (await file.exists()) {
                  await file.delete();
                }
                setState(() {
                  _downloadedSongIds.remove(songId);
                });
              }, 
              child: const Text('XÓA', style: TextStyle(color: Colors.red))
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _downloadingIds.add(songId);
    });

    try {
      final response = await http.get(Uri.parse('$baseUrl/stream/$songId'), headers: {'Cookie': globalCookie});
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          _downloadedSongIds.add(songId);
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải file: $e');
    } finally {
      setState(() {
        _downloadingIds.remove(songId);
      });
    }
  }

  Future<void> _downloadAllCurrentList() async {
    if (_isDownloadingAll) {
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Tải toàn bộ Offline?'),
        content: Text('Hệ thống sẽ tải ${_displaySongs.length} bài hát về máy.\n(Sẽ tự động bỏ qua các bài đã có)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('BẮT ĐẦU TẢI', style: TextStyle(color: Color(0xFF1DB954), fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    final List<dynamic> songsToDownload = List.from(_displaySongs);

    setState(() {
      _isDownloadingAll = true;
      _downloadAllTotal = songsToDownload.length;
      _downloadAllProgress = 0;
    });

    final dir = await getApplicationDocumentsDirectory();

    for (var song in songsToDownload) {
      if (!mounted) {
        break;
      }
      final songId = song['id'];
      
      if (_downloadedSongIds.contains(songId)) {
        setState(() {
          _downloadAllProgress++;
        });
        continue;
      }

      try {
        setState(() {
          _downloadingIds.add(songId);
        });
        
        final response = await http.get(Uri.parse('$baseUrl/stream/$songId'), headers: {'Cookie': globalCookie});
        if (response.statusCode == 200) {
          final file = File('${dir.path}/$songId.mp3');
          await file.writeAsBytes(response.bodyBytes);
          if (mounted) {
            setState(() {
              _downloadedSongIds.add(songId);
            });
          }
        }
      } catch (e) {
        debugPrint('Lỗi tải bài $songId: $e');
      } finally {
        if (mounted) {
          setState(() {
            _downloadingIds.remove(songId);
            _downloadAllProgress++;
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _isDownloadingAll = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Đã tải xong toàn bộ danh sách!'), duration: Duration(seconds: 3))
      );
    }
  }

  void _toggleSpeed() {
    setState(() {
      if (_currentSpeed == 1.0) {
        _currentSpeed = 1.25;
      } else if (_currentSpeed == 1.25) {
        _currentSpeed = 1.5;
      } else if (_currentSpeed == 1.5) {
        _currentSpeed = 0.75;
      } else {
        _currentSpeed = 1.0;
      }
    });
    _audioPlayer.setSpeed(_currentSpeed);
    _saveSettings();
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffle = !_isShuffle;
    });
    _saveSettings();
  }

  void _toggleLoop() {
    setState(() {
      _loopMode++;
      if (_loopMode > 2) {
        _loopMode = 0;
      }
    });
    _saveSettings();
  }

  void _openSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282828),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    title: const Text('Luôn phát lại từ 0:00 (Từ đầu)'),
                    activeColor: const Color(0xFF1DB954),
                    value: _playFromStart,
                    onChanged: (val) {
                      setModalState(() {
                        _playFromStart = val ?? false;
                      });
                      setState(() {
                        _playFromStart = val ?? false;
                      });
                      if (_playFromStart) {
                         setModalState(() {
                           _skipMode = false;
                         });
                         setState(() {
                           _skipMode = false;
                         });
                      }
                      _saveSettings();
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Bỏ qua đoạn đầu/cuối (Skip Mode)'),
                    activeColor: const Color(0xFF1DB954),
                    value: _skipMode,
                    onChanged: (val) {
                      setModalState(() {
                        _skipMode = val ?? false;
                      });
                      setState(() {
                        _skipMode = val ?? false;
                      });
                      if (_skipMode) {
                         setModalState(() {
                           _playFromStart = false;
                         });
                         setState(() {
                           _playFromStart = false;
                         });
                      }
                      _saveSettings();
                    },
                  ),
                  if (_skipMode)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        const Text('Cắt Đầu (s): '),
                        SizedBox(
                          width: 50,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(filled: true, fillColor: Colors.black26),
                            controller: TextEditingController(text: _skipStart.toString()),
                            onSubmitted: (val) {
                              setState(() {
                                _skipStart = int.tryParse(val) ?? 0;
                              });
                              _saveSettings();
                            },
                          ),
                        ),
                        const Text('Cắt Đuôi (s): '),
                        SizedBox(
                          width: 50,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(filled: true, fillColor: Colors.black26),
                            controller: TextEditingController(text: _skipEnd.toString()),
                            onSubmitted: (val) {
                              setState(() {
                                _skipEnd = int.tryParse(val) ?? 0;
                              });
                              _saveSettings();
                            },
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _requestFocus();
    });
  }

  Future<void> _playSong(int index, {bool autoPlay = true}) async {
    if (index < 0 || index >= _displaySongs.length) {
      return;
    }
    
    setState(() {
      _currentIndex = index;
      _currentSong = _displaySongs[index]; 
    });
    
    // THÊM 3 DÒNG NÀY ĐỂ BÁO TÊN BÀI HÁT CHO XE:
    final title = _currentSong!['name']?.replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false), '') ?? 'Unknown';
    final artist = _currentSong!['folder_path'] ?? 'Root';
    _updateNativeMetadata(title, artist);

    final songId = _currentSong!['id'];
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$songId.mp3');

      if (await file.exists()) {
        await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(file.path)));
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final streamUrl = '$baseUrl/stream/$songId?t=$timestamp';
        await _audioPlayer.setAudioSource(MyHttpAudioSource(streamUrl, globalCookie));
      }

      int startTime = 0;
      int duration = _currentSong!['duration'] != null ? (_currentSong!['duration'] is int ? _currentSong!['duration'] : int.tryParse(_currentSong!['duration'].toString()) ?? 0) : 0;
      
      if (!_playFromStart && _currentSong!['current_time'] != null) {
        int savedTime = _currentSong!['current_time'] is int ? _currentSong!['current_time'] : int.tryParse(_currentSong!['current_time'].toString()) ?? 0;
        if (savedTime > 5 && savedTime < duration - 5) {
          startTime = savedTime;
        }
      }
      if (_skipMode && startTime < _skipStart) {
        startTime = _skipStart;
      }
      if (startTime > 0) {
        await _audioPlayer.seek(Duration(seconds: startTime));
      }

      _audioPlayer.setSpeed(_currentSpeed); 
      
      if (autoPlay) {
        _audioPlayer.play();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Lỗi phát nhạc!'), backgroundColor: Colors.red)
        );
      }
    }
  }

  void _togglePlayPause() {
    if (_audioPlayer.playing) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  void _playNext() {
    if (_displaySongs.isEmpty) {
      return;
    }
    int nextIndex;
    
    if (_currentIndex == -1) {
      nextIndex = 0;
    } else if (_isShuffle && _displaySongs.length > 1) {
      do {
        nextIndex = Random().nextInt(_displaySongs.length);
      } while (nextIndex == _currentIndex); 
    } else {
      nextIndex = _currentIndex + 1;
      if (nextIndex >= _displaySongs.length) {
        nextIndex = 0;
      }
    }
    _playSong(nextIndex);
  }

  void _playPrev() {
    if (_displaySongs.isEmpty) {
      return;
    }
    int prevIndex;
    if (_currentIndex == -1) {
      prevIndex = 0;
    } else {
      prevIndex = _currentIndex - 1;
      if (prevIndex < 0) {
        prevIndex = _displaySongs.length - 1;
      }
    }
    _playSong(prevIndex);
  }

  @override
  Widget build(BuildContext context) {
    String displayFolderName = '📁 Tất cả';
    if (_currentFolder == 'offline_only') {
      displayFolderName = '⬇️ Nhạc đã tải';
    } else if (_currentFolder == 'favorites') {
      displayFolderName = '❤️ Yêu thích';
    } else if (_currentFolder == 'top100') {
      displayFolderName = '🔥 Top 100';
    } else if (_currentFolder == 'recent') {
      displayFolderName = '🆕 Mới tải';
    } else if (_currentFolder != 'all') {
      displayFolderName = '📁 $_currentFolder';
    }

    return Focus(
      focusNode: _mainFocusNode,
      autofocus: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus && !_isSearching) {
          _requestFocus();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'Tìm bài hát...', border: InputBorder.none),
                  onChanged: _searchSongs,
                )
              : const Text('🎵 N.N.Anh\'s Music (Car)'),
          backgroundColor: const Color(0xFF282828),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear(); 
                    _applyFolderFilter(_currentFolder); 
                    _requestFocus();
                  }
                });
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.folder, color: Color(0xFF1DB954)),
              onSelected: (String value) {
                _searchController.clear();
                setState(() {
                  _isSearching = false;
                });
                if (value == 'top100') {
                  _fetchSpecialList('/api/songs/top100', 'top100');
                } else if (value == 'recent') {
                  _fetchSpecialList('/api/songs/recent', 'recent');
                } else {
                  _applyFolderFilter(value);
                }
                _requestFocus();
              },
              itemBuilder: (BuildContext context) {
                List<PopupMenuEntry<String>> items = [
                  const PopupMenuItem(value: 'all', child: Text('📁 Tất cả thư mục', style: TextStyle(fontWeight: FontWeight.bold))),
                  const PopupMenuItem(value: 'favorites', child: Text('❤️ Yêu thích', style: TextStyle(fontWeight: FontWeight.bold))),
                  const PopupMenuItem(value: 'top100', child: Text('🔥 Top 100 Nghe', style: TextStyle(fontWeight: FontWeight.bold))),
                  const PopupMenuItem(value: 'recent', child: Text('🆕 Top 100 Mới', style: TextStyle(fontWeight: FontWeight.bold))),
                  const PopupMenuItem(value: 'offline_only', child: Text('⬇️ Nhạc đã tải', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1DB954)))),
                  const PopupMenuDivider(),
                ];
                for (var f in _folders) {
                  items.add(PopupMenuItem(value: f, child: Text('📁 $f')));
                }
                return items;
              },
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () { 
              setState(() {
                _isLoading = true; 
              });
              _initData(); 
            })
          ],
        ),
        body: Column(
          children: [
            if (_currentFolder != 'all' && !_isSearching)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: const Color(0xFF1DB954).withValues(alpha: 0.2), 
                child: Text('Đang lọc: $displayFolderName (${_displaySongs.length} bài)', style: const TextStyle(color: Color(0xFF1DB954), fontWeight: FontWeight.bold)),
              ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)))
                  : ListView.builder(
                      itemCount: _displaySongs.length,
                      itemBuilder: (context, index) {
                        final song = _displaySongs[index];
                        final songId = song['id'];
                        
                        final isPlaying = _currentSong != null && songId == _currentSong!['id'];
                        
                        final isDownloaded = _downloadedSongIds.contains(songId);
                        final isDownloading = _downloadingIds.contains(songId);
                        final isFavorite = song['is_favorite'] == 1; 
                        
                        return ListTile(
                          tileColor: isPlaying ? const Color(0xFF282828) : null,
                          leading: Icon(isPlaying ? Icons.bar_chart : Icons.music_note, color: isPlaying ? const Color(0xFF1DB954) : Colors.grey),
                          title: Text(
                            song['name']?.replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false), '') ?? 'Unknown',
                            style: TextStyle(color: isPlaying ? const Color(0xFF1DB954) : Colors.white, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(song['folder_path'] ?? 'Root', style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1),
                          onTap: () => _playSong(index),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: Text(isFavorite ? '❤️' : '🤍', style: const TextStyle(fontSize: 16)), onPressed: () => _toggleFavorite(songId)),
                              IconButton(
                                icon: isDownloading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1DB954)))
                                    : isDownloaded ? const Icon(Icons.check_circle, color: Color(0xFF1DB954)) : const Icon(Icons.download, color: Colors.grey),
                                onPressed: isDownloading ? null : () => _toggleDownload(songId),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            
            if (_currentFolder != 'all' && _currentFolder != 'offline_only' && _displaySongs.isNotEmpty && !_isSearching)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: const Color(0xFF121212),
                child: _isDownloadingAll
                    ? Column(
                        children: [
                          Text(
                            'Đang tải... $_downloadAllProgress / $_downloadAllTotal', 
                            style: const TextStyle(color: Color(0xFF1DB954), fontWeight: FontWeight.bold)
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _downloadAllTotal > 0 ? _downloadAllProgress / _downloadAllTotal : 0,
                            backgroundColor: Colors.grey[800],
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.download, color: Colors.white),
                          label: const Text('Tải Offline toàn bộ danh sách', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: _downloadAllCurrentList,
                        ),
                      ),
              ),

            // ==========================================
            // THANH ĐIỀU KHIỂN & BỘ KÉO THỜI GIAN (SEEKBAR)
            // ==========================================
            Container(
              color: const Color(0xFF282828),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       IconButton(icon: const Icon(Icons.settings, color: Colors.grey, size: 20), onPressed: _openSettingsDialog),
                       TextButton(
                         onPressed: _toggleSpeed,
                         style: TextButton.styleFrom(
                           padding: EdgeInsets.zero,
                           minimumSize: const Size(40, 30),
                           backgroundColor: _currentSpeed != 1.0 ? const Color(0xFF1DB954).withValues(alpha: 0.2) : Colors.transparent,
                         ),
                         child: Text('${_currentSpeed}x', style: TextStyle(color: _currentSpeed != 1.0 ? const Color(0xFF1DB954) : Colors.grey, fontWeight: FontWeight.bold)),
                       ),
                       Expanded(
                         child: Text(
                          _currentSong != null ? _currentSong!['name']?.replaceAll(RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false), '') ?? '...' : 'Chưa chọn bài hát',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                         ),
                       ),
                       IconButton(
                          iconSize: 22,
                          icon: Text(_currentSong != null && _currentSong!['is_favorite'] == 1 ? '❤️' : '🤍', style: const TextStyle(fontSize: 18)),
                          onPressed: () {
                            if (_currentSong != null) {
                              _toggleFavorite(_currentSong!['id']);
                            }
                          },
                        ),
                     ]
                  ),

                  // --- THANH KÉO TIẾN TRÌNH THỜI GIAN (SLIDER) ---
                  StreamBuilder<Duration>(
                    stream: _audioPlayer.positionStream,
                    builder: (context, snapshotPosition) {
                      final position = snapshotPosition.data ?? Duration.zero;
                      final duration = _audioPlayer.duration ?? Duration.zero;
                      
                      double maxSeconds = duration.inSeconds.toDouble();
                      double currentSeconds = _isSeeking ? _dragValue : position.inSeconds.toDouble();
                      if (currentSeconds > maxSeconds) currentSeconds = maxSeconds;

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF1DB954),
                              inactiveTrackColor: Colors.grey[700],
                              thumbColor: const Color(0xFF1DB954),
                              overlayColor: const Color(0xFF1DB954).withValues(alpha: 0.2),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                              trackHeight: 3.0,
                            ),
                            child: Slider(
                              min: 0.0,
                              max: maxSeconds > 0 ? maxSeconds : 1.0,
                              value: maxSeconds > 0 ? currentSeconds : 0.0,
                              onChangeStart: (value) {
                                setState(() {
                                  _isSeeking = true;
                                  _dragValue = value;
                                });
                              },
                              onChanged: (value) {
                                setState(() {
                                  _dragValue = value;
                                });
                              },
                              onChangeEnd: (value) {
                                if (maxSeconds > 0) {
                                  _audioPlayer.seek(Duration(seconds: value.round())).then((_) {
                                    setState(() {
                                      _isSeeking = false;
                                    });
                                  });
                                } else {
                                  setState(() {
                                    _isSeeking = false;
                                  });
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(_isSeeking ? Duration(seconds: _dragValue.round()) : position), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: 28,
                        icon: Icon(Icons.shuffle, color: _isShuffle ? const Color(0xFF1DB954) : Colors.grey),
                        onPressed: _toggleShuffle,
                      ),
                      IconButton(iconSize: 45, icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: _playPrev),
                      StreamBuilder<PlayerState>(
                        stream: _audioPlayer.playerStateStream,
                        builder: (context, snapshot) {
                          final playerState = snapshot.data;
                          if (playerState?.processingState == ProcessingState.loading || playerState?.processingState == ProcessingState.buffering) {
                            return const SizedBox(width: 60, height: 60, child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(color: Color(0xFF1DB954))));
                          } else if (playerState?.playing != true) {
                            return IconButton(iconSize: 60, icon: const Icon(Icons.play_circle_fill, color: Color(0xFF1DB954)), onPressed: _togglePlayPause);
                          } else {
                            return IconButton(iconSize: 60, icon: const Icon(Icons.pause_circle_filled, color: Color(0xFF1DB954)), onPressed: _togglePlayPause);
                          }
                        },
                      ),
                      IconButton(iconSize: 45, icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: _playNext),
                      IconButton(
                        iconSize: 28,
                        icon: Icon(_loopMode == 2 ? Icons.repeat_one : Icons.repeat, color: _loopMode != 0 ? const Color(0xFF1DB954) : Colors.grey),
                        onPressed: _toggleLoop,
                      ),
                    ],
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