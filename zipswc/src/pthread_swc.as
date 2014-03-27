/*
** ADOBE SYSTEMS INCORPORATED
** Copyright 2012 Adobe Systems Incorporated
** All Rights Reserved.
**
** NOTICE:  Adobe permits you to use, modify, and distribute this file in accordance with the
** terms of the Adobe license agreement accompanying it.  If you have received this file from a
** source other than Adobe, then your use, modification, or distribution of it requires the prior
** written permission of Adobe.
*/
package
{
  import flash.display.Sprite;
  import flash.text.TextField;
  import flash.events.Event;
  import flash.utils.setTimeout;
  import sample.pthread.CModule;
  import sample.pthread.vfs.ISpecialFile;
  import sample.pthread.spawnThread;

  public class pthread_swc extends Sprite implements ISpecialFile
  {
    public function pthread_swc()
    {
      addEventListener(Event.ADDED_TO_STAGE, initCode);
      addEventListener(Event.ENTER_FRAME, enterFrame);
      // wait 2s and spawn a thread via interface exposed by swc
      setTimeout(function():void {
        spawnThread();
      }, 2000);
    }
 
    public function initCode(e:Event):void
    {
      CModule.rootSprite = this

      if(CModule.runningAsWorker()) {
        return;
      }

      CModule.vfs.console = this;
      //CModule.startBackground(this);
      CModule.startAsync(this);
    }

    public function write(fd:int, buf:int, nbyte:int, errno_ptr:int):int
    {
      var str:String = CModule.readString(buf, nbyte);
      trace(str);
      return nbyte;
    }

    public function read(fd:int, buf:int, nbyte:int, errno_ptr:int):int
    {
      return 0
    }

    public function fcntl(fd:int, com:int, data:int, errnoPtr:int):int
    {
      return 0
    }

    public function ioctl(fd:int, com:int, data:int, errnoPtr:int):int
    {
      return 0
    }

    public function enterFrame(e:Event):void
    {
      CModule.serviceUIRequests();
    }
  }
}
