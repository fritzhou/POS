import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/receipts/data/receipt_output_service.dart';
import 'package:nexapos/features/receipts/domain/receipt_document.dart';

const channel = MethodChannel('net.nfet.printing');
const codec = StandardMethodCodec();
Future<dynamic> nativeCallback(
  String method,
  Map<String, dynamic> arguments,
) async {
  final response = Completer<ByteData?>();
  ServicesBinding.instance.channelBuffers.push(
    channel.name,
    codec.encodeMethodCall(MethodCall(method, arguments)),
    response.complete,
  );
  return codec.decodeEnvelope((await response.future)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'authorized OS print callbacks retain only the original bytes after lifecycle lock',
    () async {
      var current = true, calls = 0;
      final invoked = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'printPdf');
        calls++;
        invoked.complete(Map<String, dynamic>.from(call.arguments as Map));
        return 0;
      });
      final bytes = Uint8List.fromList(
        '%PDF-1.7\n original approved receipt'.codeUnits,
      );
      final original = Uint8List.fromList(bytes);
      const gateway = SystemReceiptOutputGateway();
      final pending = gateway.printPdf(
        bytes: bytes,
        filename: 'original_COPY.pdf',
        paper: ReceiptPaperFormat.thermal58,
        isCurrent: () => current,
      );
      final arguments = await invoked.future;
      expect(arguments['dynamic'], false);
      expect(arguments['width'], closeTo(58 * 72 / 25.4, .001));
      expect(arguments['height'], closeTo(200 * 72 / 25.4, .001));
      current = false;
      bytes.fillRange(0, bytes.length, 0);
      final pdf = await nativeCallback('onLayout', {
        'job': arguments['job'],
        'width': arguments['width'],
        'height': arguments['height'],
        'marginLeft': 0.0,
        'marginRight': 0.0,
        'marginTop': 0.0,
        'marginBottom': 0.0,
      });
      expect(pdf, original);
      await expectLater(
        Future.sync(
          () => gateway.printPdf(
            bytes: original,
            filename: 'new_COPY.pdf',
            paper: ReceiptPaperFormat.a4,
            isCurrent: () => current,
          ),
        ),
        throwsA(anything),
      );
      expect(calls, 1);
      await nativeCallback('onCompleted', {
        'job': arguments['job'],
        'completed': true,
        'error': null,
      });
      expect(await pending, true);
    },
  );
  test('native print cancellation does not imply submission', () async {
    final invoked = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      invoked.complete(Map<String, dynamic>.from(call.arguments as Map));
      return 0;
    });
    final pending = const SystemReceiptOutputGateway().printPdf(
      bytes: Uint8List.fromList('%PDF-1.7\n test copy'.codeUnits),
      filename: 'test_COPY.pdf',
      paper: ReceiptPaperFormat.a4,
      isCurrent: () => true,
    );
    final arguments = await invoked.future;
    await nativeCallback('onCompleted', {
      'job': arguments['job'],
      'completed': false,
      'error': null,
    });
    expect(await pending, false);
  });
}
