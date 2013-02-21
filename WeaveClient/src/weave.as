package
{
	import flash.display.Sprite;
	
	import mx.core.UIComponent;
	
	import weave.api.ui.ILinkableContainer;
	import weave.application.VisApp;
	import weave.cpp.CModule;

	public class weave extends Sprite
	{
		public var visApp:VisApp;
		
		public function weave()
		{
			if(!CModule.runningAsWorker())
			{
				visApp = new VisApp();
				addChild(visApp);
			}
		}
		
		// for backwards compatibility with old JavaScript evaluateExpression() code
		[Deprecated] public function get visDesktop():ILinkableContainer { return visApp.visDesktop; }
		[Deprecated] public function get flashVars():Object { return visApp.flashVars; }
		[Deprecated] public function printOrExportImage(component:UIComponent):void { visApp.printOrExportImage(component); }
	}
}
