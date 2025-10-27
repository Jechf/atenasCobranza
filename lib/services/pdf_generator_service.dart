import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class PdfGeneratorService {
  static Future<File> generarComprobantePDF({
    required String ticketNumero,
    required String reciboNumero,
    required String agencia,
    required String zona,
    required String fecha,
    required String monto,
    required String moneda,
    required String cobrador,
    required String mensaje,
  }) async {
    final pdf = pw.Document();

    // Cargar la imagen del logo
    final logoImage = await _loadLogoImage();

    // Agregar página al PDF
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Logo centrado
              if (logoImage != null)
                pw.Center(
                  child: pw.Container(
                    height: 80, // Altura del logo
                    child: pw.Image(logoImage),
                  ),
                ),

              pw.SizedBox(height: 10),

              // Encabezado
              pw.Center(
                child: pw.Text(
                  'COMPROBANTE DE COBRO',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(),

              // Resto del contenido...
              _buildInfoRow('Ticket N°:', ticketNumero),
              _buildInfoRow('Recibo N°:', reciboNumero),
              _buildInfoRow('Agencia:', agencia),
              _buildInfoRow('Zona:', zona),
              _buildInfoRow('Corte:', fecha),
              pw.SizedBox(height: 10),

              // Monto destacado
              pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'MONTO: $monto $moneda',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 10),

              // Información adicional
              _buildInfoRow('Cobrador:', cobrador),
              pw.SizedBox(height: 10),

              // Mensaje
              pw.Text(
                'Mensaje:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(mensaje),
              pw.SizedBox(height: 15),

              // Pie de página
              pw.Center(
                child: pw.Text(
                  'Sistema de Cobranza - ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Guardar PDF
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/comprobante_$ticketNumero.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  // Método para cargar la imagen del logo
  static Future<pw.MemoryImage?> _loadLogoImage() async {
    try {
      // Cargar el archivo de imagen como bytes
      final byteData = await rootBundle.load('assets/icon/logo.png');

      // Convertir a Uint8List
      final imageBytes = byteData.buffer.asUint8List();

      // Crear MemoryImage para el PDF
      return pw.MemoryImage(imageBytes);
    } catch (e) {
      debugPrint('Error cargando logo: $e');
      return null;
    }
  }

  static pw.Row _buildInfoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(flex: 3, child: pw.Text(value)),
      ],
    );
  }

  static Future<void> limpiarArchivosTemporales() async {
    try {
      final directory = await getTemporaryDirectory();
      final archivos = directory.listSync();

      for (var archivo in archivos) {
        if (archivo is File && archivo.path.endsWith('.pdf')) {
          final stat = await archivo.stat();
          final ahora = DateTime.now();
          final diferencia = ahora.difference(stat.modified);

          if (diferencia.inHours > 1) {
            await archivo.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Error limpiando archivos temporales: $e');
    }
  }
}
