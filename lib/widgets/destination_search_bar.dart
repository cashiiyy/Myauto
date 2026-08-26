import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../providers/destination_provider.dart';
import '../services/geocoding/photon_service.dart';

// ── Photon service provider ───────────────────────────────────────────────────

final _photonServiceProvider = Provider<PhotonService>((ref) {
  final service = createPhotonService();
  ref.onDispose(service.dispose);
  return service;
});

// ── Search results state ──────────────────────────────────────────────────────

final _searchResultsProvider =
    StateProvider<List<PhotonResult>>((ref) => []);

final _isLoadingProvider = StateProvider<bool>((ref) => false);

final _hasErrorProvider = StateProvider<bool>((ref) => false);

// ── Widget ────────────────────────────────────────────────────────────────────

/// Passenger-only destination search bar.
///
/// Displays a compact search field that autocompletes via Photon geocoding.
/// When a result is selected, it is stored in [destinationProvider] and a
/// destination pin marker appears on the map.
///
/// Strict UI requirements:
/// - Matches existing app theme (Color(0xFF007AFF), BorderRadius.circular(14),
///   GoogleFonts.inter, white background, subtle shadow).
/// - Does NOT trigger any booking, matching, payment, or status change.
/// - Hidden for driver role — shown only from the passenger map view.
class DestinationSearchBar extends ConsumerStatefulWidget {
  const DestinationSearchBar({super.key});

  @override
  ConsumerState<DestinationSearchBar> createState() =>
      _DestinationSearchBarState();
}

class _DestinationSearchBarState extends ConsumerState<DestinationSearchBar> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  bool _overlayOpen = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  static const _accentColor = Color(0xFF007AFF);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    }
  }

  // ── Search logic ───────────────────────────────────────────────────────────

  void _onTextChanged(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      ref.read(_searchResultsProvider.notifier).state = [];
      ref.read(_isLoadingProvider.notifier).state = false;
      ref.read(_hasErrorProvider.notifier).state = false;
      _removeOverlay();
      return;
    }

    ref.read(_isLoadingProvider.notifier).state = true;
    ref.read(_hasErrorProvider.notifier).state = false;

    _debounceTimer = Timer(
      Duration(milliseconds: AppConfig.photonDebounceMs),
      () => _doSearch(query.trim()),
    );
  }

  Future<void> _doSearch(String query) async {
    if (!mounted) return;

    final photon = ref.read(_photonServiceProvider);
    final results = await photon.search(query);

    if (!mounted) return;

    ref.read(_searchResultsProvider.notifier).state = results;
    ref.read(_isLoadingProvider.notifier).state = false;

    if (results.isEmpty && query.isNotEmpty) {
      ref.read(_hasErrorProvider.notifier).state = false; // empty is fine
    }

    if (_focusNode.hasFocus) {
      _showOverlay();
    }
  }

  void _onResultSelected(PhotonResult result) {
    // Store selected destination — does NOT trigger booking
    ref.read(destinationProvider.notifier).state = DestinationPlace(
      displayLabel: result.displayLabel,
      placeName: result.placeName,
      latitude: result.latitude,
      longitude: result.longitude,
    );

    _textController.text = result.displayLabel;
    ref.read(_searchResultsProvider.notifier).state = [];
    _focusNode.unfocus();
    _removeOverlay();
  }

  void _clearDestination() {
    _textController.clear();
    ref.read(destinationProvider.notifier).state = null;
    ref.read(_searchResultsProvider.notifier).state = [];
    ref.read(_isLoadingProvider.notifier).state = false;
    _removeOverlay();
    _focusNode.requestFocus();
  }

  // ── Overlay management ────────────────────────────────────────────────────

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) => _buildOverlay());
    overlay.insert(_overlayEntry!);
    setState(() => _overlayOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _overlayOpen = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(destinationProvider);
    final isLoading = ref.watch(_isLoadingProvider);
    final hasDestination = destination != null;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: hasDestination
                ? _accentColor.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.15),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              hasDestination ? Icons.place : Icons.search,
              color: hasDestination ? _accentColor : Colors.grey.shade500,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                onChanged: _onTextChanged,
                style: GoogleFonts.inter(fontSize: 14, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Where to?',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (isLoading)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: _accentColor.withValues(alpha: 0.7),
                  ),
                ),
              )
            else if (_textController.text.isNotEmpty)
              GestureDetector(
                onTap: _clearDestination,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final results = ref.watch(_searchResultsProvider);
    final isLoading = ref.watch(_isLoadingProvider);
    final query = _textController.text.trim();

    return Positioned(
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 52), // below the search bar
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 32,
              maxHeight: 240,
            ),
            child: _buildOverlayContent(results, isLoading, query),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayContent(
    List<PhotonResult> results,
    bool isLoading,
    String query,
  ) {
    if (isLoading && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: _accentColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Searching…',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (!isLoading && results.isEmpty && query.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined,
                size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 10),
            Text(
              'No places found for "$query"',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Colors.grey.shade100,
        indent: 44,
      ),
      itemBuilder: (_, index) {
        final result = results[index];
        return InkWell(
          onTap: () => _onResultSelected(result),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 18, color: _accentColor.withValues(alpha: 0.8)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        result.placeName.isNotEmpty
                            ? result.placeName
                            : result.displayLabel,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result.displayLabel != result.placeName &&
                          result.displayLabel.isNotEmpty)
                        Text(
                          result.displayLabel,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
