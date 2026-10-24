import unittest
from unittest.mock import patch
from .provider import transcribe, AssistantError


class TranscriptionTests(unittest.TestCase):
    @patch('app.modules.asistente_ia.provider.call')
    def test_empty_transcript_reports_no_recognized_voice(self, call):
        for result in ({'text': ''}, {'text': ' \n '}):
            call.return_value = result
            with self.assertRaises(AssistantError) as raised:
                transcribe(b'audio', 'audio/webm')
            self.assertEqual(raised.exception.status, 422)

    @patch('app.modules.asistente_ia.provider.call')
    def test_invalid_response_is_not_silent_success(self, call):
        for result in ({}, {'text': None}, {'text': 4}, []):
            call.return_value = result
            with self.assertRaises(AssistantError) as raised:
                transcribe(b'audio', 'audio/webm')
            self.assertEqual(raised.exception.status, 502)

    @patch('app.modules.asistente_ia.provider.call', return_value={'text': '  Consulta la carta.  '})
    def test_codec_mime_and_explicit_json(self, call):
        self.assertEqual(transcribe(b'audio', 'audio/webm;codecs=opus'), 'Consulta la carta.')
        path, body, content_type = call.call_args.args
        self.assertEqual(path, 'audio/transcriptions')
        self.assertIn(b'name="response_format"\r\n\r\njson', body)
        self.assertIn(b'filename="dictado.webm"', body)
        self.assertIn('multipart/form-data', content_type)

    @patch('app.modules.asistente_ia.provider.call')
    def test_invalid_audio_does_not_call_provider(self, call):
        for content, mime in ((b'', 'audio/webm'), (b'audio', 'text/plain')):
            with self.assertRaises(AssistantError): transcribe(content, mime)
        call.assert_not_called()
