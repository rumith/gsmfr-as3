﻿package {

	import org.glavbot.codecs.gsmfr.GSM;
	import org.glavbot.codecs.gsmfr.GSMDecoder;
	import org.glavbot.codecs.gsmfr.GSMEncoder;

	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.SampleDataEvent;
	import flash.events.StatusEvent;
	import flash.media.Microphone;
	import flash.media.Sound;
	import flash.media.SoundCodec;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;
	import flash.utils.ByteArray;

	/**
	 * @author Vasiliy Vasilyev
	 */
	[SWF(backgroundColor="#000000", frameRate="60", width="640", height="480")]
	public class MicrophoneEncodeDecodeTest extends Sprite {

		public static const SAMPLE_RATE: int = 44100;
		public static const FRAME_SAMPLES: int = GSM.FRAME_SAMPLES * SAMPLE_RATE / GSM.SAMPLE_RATE;

		private var microphone: Microphone;
		private var encoder: GSMEncoder;
		private var field: TextField;
		private var frame: Vector.<int> = new <int>[];
		private var inputBitmap: BitmapData;
		private var outputBitmap: BitmapData;
		private var decoder: GSMDecoder;
		private var sound: Sound;

		public function MicrophoneEncodeDecodeTest() {
			try {
				initStage();
				initView();
				initEncoder();
				initDecoder();
				initMicrophone();
				initSound();
			} catch (error: *) {
				trace(error);
			}
		}

		private function initDecoder(): void {
			decoder = new GSMDecoder();
		}

		private function initStage(): void {
			stage.align = StageAlign.TOP_LEFT;
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.showDefaultContextMenu = false;
			stage.stageFocusRect = false;
			stage.frameRate = 60;
		}

		private function initView(): void {
			field = new TextField();
			field.defaultTextFormat = new TextFormat("_typewriter", 12, 0xffff00);
			field.autoSize = TextFieldAutoSize.LEFT;
			field.multiline = true;
			field.wordWrap = false;
			field.selectable = false;
			field.mouseEnabled = false;
			field.y = 260;
			addChild(field);

			addChild(new Bitmap(inputBitmap = new BitmapData(640, 128, false, 0x002200)));
			addChild(new Bitmap(outputBitmap = new BitmapData(640, 128, false, 0x220000))).y = 128;
		}

		private function initEncoder(): void {
			encoder = new GSMEncoder();
		}

		private function initMicrophone(): void {
			microphone = Microphone.getEnhancedMicrophone();

			if (microphone) {
				
				microphone.setUseEchoSuppression(true);
				microphone.setLoopBack(false);
				microphone.encodeQuality = 6;
				microphone.setSilenceLevel(0);
				microphone.gain = 75;
				microphone.rate = 44;
				microphone.framesPerPacket = 1;
				microphone.codec = SoundCodec.SPEEX;
				microphone.addEventListener(StatusEvent.STATUS, _status);
				microphone.addEventListener(SampleDataEvent.SAMPLE_DATA, _sample);

			} else {
				throw new Error("No microphone found");
			}
		}

		var input: ByteArray = new ByteArray();

		private function initSound(): void {
			sound = new Sound();
			sound.addEventListener(SampleDataEvent.SAMPLE_DATA, _sampleout);
			sound.play();
		}

		private function _sampleout(event: SampleDataEvent): void {
			try {
				// Minimum required samples count is 2048

				var samples: int = 2048;
				var i: int;

				while (samples > 0 && input.bytesAvailable >= GSM.FRAME_SIZE * 2) {
					// Decode frame

					var frame: Vector.<int> = decoder.decode(input);
					var scale: Number = GSM.FRAME_SAMPLES / FRAME_SAMPLES;
					
					for (i = 0; i < GSM.FRAME_SAMPLES; i++) {
						var recoded: int = outputBitmap.height * (0.5 + frame[i] * 0.5 / 32768);
						outputBitmap.setPixel(1, recoded, 0xff0000);
						outputBitmap.scroll(1, 0);
					}

					// Resample 8000Hz --> 44100Hz

					for (i = 0; i < FRAME_SAMPLES; i++) {

						// Convert 16bit PCM to float PCM and Write

						var value: Number = frame[int(i * scale)] / 32768;
						event.data.writeFloat(value);
						event.data.writeFloat(value);
					}

					samples -= FRAME_SAMPLES;
				}

				// Write silence if no data

				while (samples-- > 0) {
					event.data.writeFloat(0);
					event.data.writeFloat(0);
				}

				field.text = "GSM-FR Encoding + Decoding Loopback\n" +
					"Input: " + microphone.name + "\n" +
					"Output: Sound Object\n";

			} catch (e: Error) {
				trace(e.getStackTrace());
			}
		}

		private function _sample(event: SampleDataEvent): void {

			var scale: Number = GSM.FRAME_SAMPLES / FRAME_SAMPLES;
			var data: ByteArray = event.data;
			var bytes: ByteArray;
			var i: int;

			// Sample contains 2560 bytes / 320 PCM samples

			while (data.bytesAvailable > 0) {
				// Read and Convert float PCM to 16bit PCM

				frame.push(GSM.saturate(data.readFloat() * 32768));

				if (frame.length == FRAME_SAMPLES) {

					// Resample 44100Hz --> 8000Hz

					var sum: int = 1;
					var old: int;
					var index: int;

					for (i = 1; i < FRAME_SAMPLES; i++) {
						index = int(i * scale);

						if (old != index) {
							frame[old] = frame[old] / sum;
							sum = 1;
							old = index;
						} else {
							sum++;
						}

						frame[index] += frame[i];
					}

					index = FRAME_SAMPLES - 1;
					frame[index] = frame[index] / sum;
					bytes = encoder.encode(frame);

					// Store bytes

					var position: int = input.position;
					input.position = input.length;
					input.writeBytes(bytes);
					input.position = position;

					// Draw comparison graph

					for (i = 0; i < GSM.FRAME_SAMPLES; i++) {
						var recoded: int = inputBitmap.height * (0.5 + frame[i] * 0.5 / 32768);
						inputBitmap.setPixel(1, recoded, 0x00ff00);
						inputBitmap.scroll(1, 0);
					}

					frame.length = 0;
				}

			}

			/*try {
			var data:ByteArray = event.data;
			var count:int = data.bytesAvailable / 16;
			var left:Number;
			var right: Number;
			var frame: Vector.<Number> = this.frame;
			var index:int = frame.length;
			var size:int = GSMEncoder.FRAME_SIZE;
								
			for(var i:int = 0; i < count; i++) {
			left = data.readFloat();
			right = data.readFloat();
					
			// TODO: resample...
			// TODO: try different types of left+right channel mixing
					
			frame[index++] = (left + right) / 2;
					
			if (index == size) {
			encoder.encode(frame);
			frame.length = index = 0;
			}
					
			left = int(left * 127);
			right = int(right * 127);
					
			if (left == right) {
			bitmap.setPixel(1, 128 + left, 0xffff00);						
			} else {
			bitmap.setPixel(1, 128 + left, 0x00ff00);
			bitmap.setPixel(1, 128 + right, 0xff0000);
			}
			bitmap.scroll(1, 0);	
			}				
			} catch (error:*) {
			trace(error);
			}*/
		}

		private function _status(event: StatusEvent): void {
			trace(event.type);
		}
	}
}
