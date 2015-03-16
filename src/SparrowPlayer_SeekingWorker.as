package
{
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLRequest;
	import flash.net.URLStream;
	import flash.system.MessageChannel;
	import flash.system.Security;
	import flash.system.Worker;
	import flash.utils.ByteArray;
	/**
	 *  
	 * @author yangq1990
	 * 
	 */	
	public class SparrowPlayer_SeekingWorker extends Sprite
	{
		/** 命令通道 **/
		private var _cmdChannel:MessageChannel;
		/** 状态通道 **/
		private var _stateChannel:MessageChannel;
		/** URLStream提供了对字节层面的访问 **/
		private var _urlStream:URLStream;
		private var _kfFilePos:Number = 0;
		/** 未加密的字节数据 **/
		private var _omittedLength:Number = 0;
		/** 加密算法种子 **/
		private var _seed:int = 0;		
		/** 是否第一次添加 **/
		private var _firstAppend:Boolean = true;
		
		public function SparrowPlayer_SeekingWorker()
		{
			init();	
		}
		
		private function init():void
		{
			try
			{
				Security.allowDomain("*");
				_cmdChannel = Worker.current.getSharedProperty("incomingCmdToSeekingWorker") as MessageChannel;
				_cmdChannel.addEventListener(Event.CHANNEL_MESSAGE, cmdChannelMsgHandler);
				
				_stateChannel = Worker.current.getSharedProperty("seekingWorkerStateChannel") as MessageChannel;
				_stateChannel.send(["seeking_worker_ready"]); //tell main worker that child worker is ready
			}
			catch(err:Error)
			{
				trace(err.getStackTrace());
			}			
		}
		
		private function cmdChannelMsgHandler(event:Event):void
		{
			if (!_cmdChannel.messageAvailable)
				return;
			
			var message:Array = _cmdChannel.receive() as Array;
			if(message != null)
			{
				switch(message[0])
				{
					case "doSeek":						
						destroyUrlStream();
						
						_kfFilePos = message[2];
						_omittedLength = message[3];
						_seed = message[4];						
						_urlStream = new URLStream();
						_urlStream.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
						_urlStream.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
						_urlStream.addEventListener(ProgressEvent.PROGRESS,progressHandler);  
						_urlStream.addEventListener(Event.COMPLETE,completeHnd);  
						_urlStream.load(new URLRequest(message[1] + "?start=" + _kfFilePos));
						break;
					default:
						break;
				}
			}
			else
			{
				_stateChannel.send(["seeking_error", "seek时发生错误"]);
			}
		}
		
		/** 释放拖动时启动的urlstream所占的资源 **/
		private function destroyUrlStream():void
		{
			if(_urlStream)
			{
				_firstAppend = true;
				_urlStream.close();
				_urlStream.removeEventListener(ProgressEvent.PROGRESS, progressHandler);
				_urlStream.removeEventListener(Event.COMPLETE, completeHnd);
				_urlStream.removeEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
				_urlStream.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
				_urlStream = null;
			}
		}
		
		/** security error  **/
		private function securityErrorHandler(evt:SecurityErrorEvent):void
		{
			_stateChannel.send(["seeking_error", evt.toString()]);
		}		
		
		private function ioErrorHandler(evt:IOErrorEvent):void
		{
			_stateChannel.send(["seeking_error", evt.toString()]);
		}				
		
		/** 加载加密视频中 **/
		private function progressHandler(evt:ProgressEvent):void
		{				
			var bytes:ByteArray = new ByteArray();
			_urlStream.readBytes(bytes, 0, _urlStream.bytesAvailable);
			bytes.position = 0;
			
			var tempValue:int;
			var streamBytes:ByteArray = new ByteArray(); //要添加到_stream的bytearray
			streamBytes.shareable = true;			
			if(_firstAppend)
			{
				_firstAppend = false;
				var len:int = bytes.length;		
				//第一次添加的前13个字节不做处理，这13个字节是nginx给返回的字节数据自动添加的，就是flv header(9字节) + first tag size(4字节)	
				for(var j:int=0; j < 13; j++)  		
				{
					tempValue = bytes.readByte();
					streamBytes.writeByte(tempValue);
				}
				
				bytes.position = 13;
				for(var i:int=13; i < len; i++)
				{
					tempValue = bytes.readByte();
					tempValue -= 128;
					streamBytes.writeByte(tempValue);
				}	
			}
			else
			{
				while(bytes.bytesAvailable)					
				{
					tempValue = bytes.readByte();
					tempValue -= 128;
					streamBytes.writeByte(tempValue);
				}				
			}	
			
			_stateChannel.send(["seeking_load_progress", evt.bytesLoaded/evt.bytesTotal,  evt.bytesTotal, streamBytes]);
		}  
		
		/** 加载完成 **/
		private function completeHnd(e:Event):void
		{					
			_stateChannel.send(["seeking_load_complete"]);
			destroyUrlStream();
		} 
	}
}