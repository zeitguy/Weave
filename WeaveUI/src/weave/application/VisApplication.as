/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.application
{
	import flash.display.LoaderInfo;
	import flash.display.StageDisplayState;
	import flash.events.ContextMenuEvent;
	import flash.events.Event;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.external.ExternalInterface;
	import flash.geom.Point;
	import flash.net.FileFilter;
	import flash.net.FileReference;
	import flash.net.SharedObject;
	import flash.net.URLRequest;
	import flash.net.URLVariables;
	import flash.net.navigateToURL;
	import flash.system.Capabilities;
	import flash.ui.ContextMenu;
	import flash.ui.ContextMenuItem;
	import flash.utils.ByteArray;
	import flash.utils.Timer;
	import flash.utils.getQualifiedClassName;
	import flash.utils.getTimer;
	
	import mx.collections.ArrayCollection;
	import mx.containers.VBox;
	import mx.controls.Alert;
	import mx.controls.Button;
	import mx.controls.Image;
	import mx.controls.Text;
	import mx.core.IToolTip;
	import mx.core.UIComponent;
	import mx.effects.Fade;
	import mx.events.EffectEvent;
	import mx.events.FlexEvent;
	import mx.managers.PopUpManager;
	import mx.managers.ToolTipManager;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	
	import spark.components.Group;
	
	import weave.Weave;
	import weave.WeaveProperties;
	import weave.api.WeaveAPI;
	import weave.api.core.ICallbackCollection;
	import weave.api.core.ILinkableHashMap;
	import weave.api.core.ILinkableObject;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IDataSource;
	import weave.api.detectLinkableObjectChange;
	import weave.api.getCallbackCollection;
	import weave.api.objectWasDisposed;
	import weave.api.reportError;
	import weave.api.ui.IVisTool;
	import weave.api.ui.IVisToolWithSelectableAttributes;
	import weave.compiler.StandardLib;
	import weave.core.ExternalSessionStateInterface;
	import weave.core.LinkableBoolean;
	import weave.data.DataSources.WeaveDataSource;
	import weave.data.KeySets.KeySet;
	import weave.editors.SingleImagePlotterEditor;
	import weave.editors.WeavePropertiesEditor;
	import weave.editors.managers.DataSourceManager;
	import weave.services.LocalAsyncService;
	import weave.services.addAsyncResponder;
	import weave.ui.AlertTextBox;
	import weave.ui.AlertTextBoxEvent;
	import weave.ui.AttributeSelectorPanel;
	import weave.ui.CirclePlotterSettings;
	import weave.ui.ColorController;
	import weave.ui.CustomContextMenuManager;
	import weave.ui.CustomToolTipBorder;
	import weave.ui.DraggablePanel;
	import weave.ui.EquationEditor;
	import weave.ui.ErrorLogPanel;
	import weave.ui.ExportSessionStateOptions;
	import weave.ui.NewUserWizard;
	import weave.ui.OICLogoPane;
	import weave.ui.PenTool;
	import weave.ui.PrintPanel;
	import weave.ui.ProbeToolTipEditor;
	import weave.ui.ProbeToolTipWindow;
	import weave.ui.QuickMenuPanel;
	import weave.ui.SelectionManager;
	import weave.ui.SessionStateEditor;
	import weave.ui.SubsetManager;
	import weave.ui.WeaveProgressBar;
	import weave.ui.WizardPanel;
	import weave.ui.annotation.SessionedTextBox;
	import weave.ui.collaboration.CollaborationEditor;
	import weave.ui.collaboration.CollaborationMenuBar;
	import weave.ui.collaboration.CollaborationTool;
	import weave.ui.controlBars.VisTaskbar;
	import weave.ui.controlBars.WeaveMenuBar;
	import weave.ui.controlBars.WeaveMenuItem;
	import weave.utils.ColumnUtils;
	import weave.utils.DebugTimer;
	import weave.utils.EditorManager;
	import weave.utils.VectorUtils;
	import weave.visualization.tools.WeaveAnalyst;

	internal class VisApplication extends VBox implements ILinkableObject
	{
		MXClasses; // Referencing this allows all Flex classes to be dynamically created at runtime.
		
		SessionStateEditor.initialize; // adds keyboard shortcut & upper-left click shortcut

		/**
		 * Constructor.
		 */
		public function VisApplication()
		{
			super();

			setStyle("paddingLeft", 0);
			setStyle("paddingRight", 0);
			setStyle("paddingTop", 0);
			setStyle("paddingBottom", 0);
			
			setStyle("marginLeft", 0);
			setStyle("marginRight", 0);
			setStyle("marginTop", 0);
			setStyle("marginBottom", 0);
			
			setStyle("verticalGap", 0);
			setStyle("horizingalGap", 0);
			setStyle('backgroundAlpha', 1);
			
			// make it so the menu bar does not get hidden if the workspace size is too small.
			clipContent = false;
			autoLayout = true;
			
			// no scrolling
			horizontalScrollPolicy = "off";
			verticalScrollPolicy   = "off";
			visDesktop.verticalScrollPolicy   = "off";
			visDesktop.horizontalScrollPolicy = "off";
			
			percentWidth = 100;
			percentHeight = 100;

			callLater(waitForApplicationComplete);
		}

		/**
		 * This needs to be a function because FlashVars can't be fetched while the application is loading.
		 */
		private function waitForApplicationComplete():void
		{
			if (!root)
			{
				callLater(waitForApplicationComplete);
				return;
			}
			
			try {
				loaderInfo['uncaughtErrorEvents'].addEventListener(
					'uncaughtError',
					function(event:Object):void
					{
						reportError(event.error);
					}
				);
			} catch (e:Error) { }
			
			// resize to parent size each frame because percentWidth,percentHeight doesn't seem reliable when application is nested
			addEventListener(Event.ENTER_FRAME, updateWorkspaceSize);
			
			getCallbackCollection(WeaveAPI.ErrorManager).addGroupedCallback(this, handleError, WeaveAPI.ErrorManager.errors.length > 0);
			WeaveAPI.globalHashMap.childListCallbacks.addGroupedCallback(this, setupWindowMenu);
			Weave.properties.showCopyright.addGroupedCallback(this, toggleMenuBar);
			Weave.properties.enableMenuBar.addGroupedCallback(this, toggleMenuBar);
			Weave.properties.enableCollaborationBar.addGroupedCallback(this, toggleCollaborationMenuBar);
			Weave.properties.pageTitle.addGroupedCallback(this, updatePageTitle);
			
			getCallbackCollection(Weave.savedSelectionKeySets).addGroupedCallback(this, setupSelectionsMenu);
			getCallbackCollection(Weave.savedSubsetsKeyFilters).addGroupedCallback(this, setupSubsetsMenu);
			getCallbackCollection(Weave.properties).addGroupedCallback(this, setupVisMenuItems);
			Weave.properties.backgroundColor.addImmediateCallback(this, invalidateDisplayList, true);

			if (ExternalInterface.available)
				ExternalInterface.addCallback('loadFile', loadFile);
			WeaveAPI.initializeExternalInterface();

			getFlashVars();
			handleFlashVarPresentation();
			handleFlashVarAllowDomain();
			
			// disable application until it's ready
			enabled = false;
			
			if (getFlashVarAdminConnectionName())
			{
				// disable interface while connecting to admin console
				var _this:VisApplication = this;
				_this.enabled = false;
				
				var pendingAdminService:LocalAsyncService = new LocalAsyncService(this, false, getFlashVarAdminConnectionName());
				addAsyncResponder(
					pendingAdminService.invokeAsyncMethod("ping"),
					function(event:ResultEvent, token:Object = null):void
					{
						// when admin console responds, set adminService
						adminService = pendingAdminService;
						saveTimer.addEventListener(TimerEvent.TIMER, saveRecoverPoint);
						saveTimer.start();
						
						_this.enabled = true;
						setupVisMenuItems(); // make sure 'save session state to server' is shown
						downloadConfigFile();
					},
					function(event:FaultEvent = null, token:Object = null):void
					{
						Alert.show(lang("Unable to connect to the Admin Console.\nYou will not be able to save your session state to the server."), lang("Connection error"));
						
						_this.enabled = true;
						setupVisMenuItems();
						downloadConfigFile();
					}
				);
			}
			else
			{
				downloadConfigFile();
			}
		}

		private function handleError():void
		{
			if (Weave.properties.showErrors.value)
				ErrorLogPanel.openErrorLog();
		}
		
		private var _requestedConfigFile:String;
		private var _loadFileCallback:Function;
		/**
		 * Loads a session state file from a URL.
		 * @param url The URL to the session state file (.weave or .xml).
		 * @param callback Either a Function or a String containing a JavaScript function definition. The callback will be invoked when the file loading completes.
		 * @param noCacheHack If set to true, appends "?" followed by a series of numbers to prevent Flash from using a cached version of the file.
		 */
		public function loadFile(url:String, callback:Object = null, noCacheHack:Boolean = false):void
		{
			_requestedConfigFile = url;
			_loadFileCallback = callback as Function;
			if (callback is String)
				_loadFileCallback = function():void { ExternalInterface.call(callback as String); };
			
			if (noCacheHack)
				url += "?" + (new Date()).getTime(); // prevent flex from using cache
			
			WeaveAPI.URLRequestUtils.getURL(null, new URLRequest(url), handleConfigFileDownloaded, handleConfigFileFault, _requestedConfigFile);
		}
		
		private function downloadConfigFile():void
		{
			_loadFileCallback = null;
			if (getFlashVarRecover() || Weave.handleWeaveReload())
			{
				handleConfigFileDownloaded();
			}
			else
			{
				var fileName:String = getFlashVarFile() || DEFAULT_CONFIG_FILE_NAME;
				loadFile(fileName, null, true);
			}
		}
		private function handleConfigFileDownloaded(event:ResultEvent = null, fileName:String = null):void
		{
			if (!event)
			{
				loadSessionState(null, null);
			}
			else
			{
				// ignore old requests
				if (fileName != _requestedConfigFile)
					return;
				if (Capabilities.playerType == "Desktop")
					WeaveAPI.URLRequestUtils.setBaseURL(fileName);
				loadSessionState(event.result, fileName);
			}
			
			if (getFlashVarEditable())
			{
				Weave.properties.enableMenuBar.value = true;
				Weave.properties.enableSessionMenu.value = true;
				Weave.properties.enableWindowMenu.value = true;
				Weave.properties.enableUserPreferences.value = true;
			}
			else if (getFlashVarEditable() === false) // triple equals because it may also be undefined
			{
				Weave.properties.enableMenuBar.value = false;
				Weave.properties.dashboardMode.value = true;
			}
			if (_loadFileCallback != null)
				_loadFileCallback();
			WeaveAPI.callExternalWeaveReady();
		}
		private function handleConfigFileFault(event:FaultEvent, fileName:String):void
		{
			// don't report an error if no filename was specified
			var noFileName:Boolean = !getFlashVarFile();
			if (noFileName)
			{
				// for default fallback configuration, create a WeaveDataSource
				WeaveAPI.globalHashMap.requestObject(null, WeaveDataSource, false);
				
				// if not opened from admin console, enable interface now
				if (!getFlashVarAdminConnectionName())
					this.enabled = true;
				WeaveAPI.callExternalWeaveReady();
			}
			else
			{
				reportError(event);
				if (event.fault.faultCode == SecurityErrorEvent.SECURITY_ERROR)
					Alert.show(lang("The server hosting the configuration file does not have a permissive crossdomain policy."), lang("Security sandbox violation"));
			}
		}
		
		override protected function updateDisplayList(unscaledWidth:Number, unscaledHeight:Number):void
		{
			var color:Number = Weave.properties.backgroundColor.value;
			this.graphics.clear();
			this.graphics.beginFill(color);
			this.graphics.drawRect(0, 0, unscaledWidth, unscaledHeight);
			
			super.updateDisplayList(unscaledWidth, unscaledHeight);
		}
		
		/**
		 * The desktop is the entire viewable area minus the space for the optional menu bar and taskbar
		 */
		public const visDesktop:VisDesktop = new VisDesktop();

		/**
		 * The mapping for the flash vars.
		 */
		private var _flashVars:Object;
		public function get flashVars():Object { return _flashVars; }
		
		private function handleFlashVarPresentation():void
		{
			var presentationMode:Boolean = StandardLib.asBoolean(_flashVars['presentation'] as String);
			Weave.history.enableLogging.value = !presentationMode;
		}
		
		private function handleFlashVarAllowDomain():void
		{
			var domains:* = _flashVars['allowDomain'];
			if (domains is String)
				domains = [domains];
			for each (var domain:String in domains)
			{
				systemManager.allowDomain(domain);
				systemManager.allowInsecureDomain(domain);
			}
		}
		
		private function getFlashVarAdminConnectionName():String
		{
			return _flashVars['adminSession'] as String;
		}
		private function getFlashVarRecover():Boolean
		{
			return StandardLib.asBoolean(_flashVars['recover'] as String);
		}
		
		/**
		 * Gets the name of the config file.
		 */
		private function getFlashVarFile():String
		{
			return unescape(_flashVars[CONFIG_FILE_FLASH_VAR_NAME] || '');
		}
		
		/**
		 * @return true, false, or undefined depending what the 'editable' FlashVar is set to.
		 */
		private function getFlashVarEditable():*
		{
			var name:String = 'editable';
			if (_flashVars.hasOwnProperty(name))
				return StandardLib.asBoolean(_flashVars[name] as String);
			return undefined;
		}
		
		public function setFlashVars(vars:Object):void
		{
			_flashVars = vars;
		}
		
		/**
		 * Gets the flash vars.
		 */
		private function getFlashVars():void
		{
			if (_flashVars)
				return;
			
			// We want FlashVars to take priority over the address bar parameters.
			_flashVars = LoaderInfo(this.root.loaderInfo).parameters;
			
			// check address bar for any variables not found in FlashVars
			try
			{
				var urlParams:URLVariables = new URLVariables(ExternalInterface.call("window.location.search.substring", 1)); // text after '?'
				for (var key:String in urlParams)
					if (!_flashVars.hasOwnProperty(key)) // flashvars take precedence over url params
						_flashVars[key] = urlParams[key];
				
				// backwards compatibility with old param name
				const DEPRECATED_FILE_PARAM_NAME:String = 'defaults';
				if (!_flashVars.hasOwnProperty(CONFIG_FILE_FLASH_VAR_NAME) && urlParams.hasOwnProperty(DEPRECATED_FILE_PARAM_NAME))
				{
					_flashVars[CONFIG_FILE_FLASH_VAR_NAME] = urlParams[DEPRECATED_FILE_PARAM_NAME];
					_usingDeprecatedFlashVar = true;
				}
			}
			catch(e:Error) { }
		}
		private static const CONFIG_FILE_FLASH_VAR_NAME:String = 'file';
		private static const DEFAULT_CONFIG_FILE_NAME:String = 'defaults.xml';
		private var _usingDeprecatedFlashVar:Boolean = false;
		private const DEPRECATED_FLASH_VAR_MESSAGE:String = lang("The 'defaults=' URL parameter is deprecated.  Use 'file=' instead.");

		private var _selectionIndicatorText:Text = new Text();
		private var selectionKeySet:KeySet = Weave.defaultSelectionKeySet;
		private function handleSelectionChange():void
		{
			_selectionIndicatorText.text = lang("{0} Records Selected", selectionKeySet.keys.length.toString());
			try
			{
				var show:Boolean = Weave.properties.showSelectedRecordsText.value && selectionKeySet.keys.length > 0;
				if (show)
				{
					if (visDesktop != _selectionIndicatorText.parent)
						visDesktop.addChild(_selectionIndicatorText);
						
					if( Weave.properties.recordsTooltipLocation.value == WeaveProperties.RECORDS_TOOLTIP_LOWER_LEFT ){
						_selectionIndicatorText.setStyle( "left", 0 ) ;
						_selectionIndicatorText.setStyle( "right", null ) ;
					}
					else if( Weave.properties.recordsTooltipLocation.value == WeaveProperties.RECORDS_TOOLTIP_LOWER_RIGHT ){
						_selectionIndicatorText.setStyle( "right", 0 ) ;
						_selectionIndicatorText.setStyle( "left", null ) ;
					}	
				}
				else
				{
					if (visDesktop == _selectionIndicatorText.parent)
						visDesktop.removeChild(_selectionIndicatorText);
				}
			}
			catch (e:Error)
			{
				reportError(e);
			}
		}
		
		private var historySlider:UIComponent = null;
		
		override protected function createChildren():void
		{
			super.createChildren();

			//UIComponentGlobals.catchCallLaterExceptions = true;
			//systemManager.addEventListener("callLaterError", reportError);

			this.addChild(visDesktop);
			visDesktop.percentWidth = 100;
			visDesktop.percentHeight = 100;
			Weave.properties.workspaceWidth.addImmediateCallback(this, updateWorkspaceSize);
			Weave.properties.workspaceHeight.addImmediateCallback(this, updateWorkspaceSize);
			Weave.properties.workspaceMultiplier.addImmediateCallback(this, updateWorkspaceSize);
			
			// Code for selection indicator
			getCallbackCollection(selectionKeySet).addGroupedCallback(this, handleSelectionChange, true);
			Weave.properties.showSelectedRecordsText.addGroupedCallback(this, handleSelectionChange, true);
			Weave.properties.recordsTooltipLocation.addGroupedCallback(this, handleSelectionChange, true);
			
			_selectionIndicatorText.setStyle("color", 0xFFFFFF);
			_selectionIndicatorText.opaqueBackground = 0x000000;
			_selectionIndicatorText.setStyle("bottom", 0);
			_selectionIndicatorText.setStyle("left", 0);
			
			PopUpManager.createPopUp(this, WeaveProgressBar);

			this.addChild(VisTaskbar.instance);
			WeaveAPI.StageUtils.addEventCallback(KeyboardEvent.KEY_DOWN,this,handleKeyPress);
		}
		
		private function handleKeyPress():void
		{
			var event:KeyboardEvent = WeaveAPI.StageUtils.keyboardEvent;
			if(event.ctrlKey && event.keyCode == 77)
			{
				var qmenu:QuickMenuPanel = PopUpManager.createPopUp(this,QuickMenuPanel) as QuickMenuPanel;
				PopUpManager.centerPopUp(qmenu);
			}
		}
		
		private function updateWorkspaceSize(..._):void
		{
			if (!this.parent)
				return;
			
			var w:Number = Weave.properties.workspaceWidth.value;
			var h:Number = Weave.properties.workspaceHeight.value;
			if (isFinite(w))
				this.width = w;
			else
				this.width = this.parent.width;
			if (isFinite(h))
				this.height = h;
			else
				this.height = this.parent.height;
			
			var workspace:Group = visDesktop.workspace;
			var multiplier:Number = Weave.properties.workspaceMultiplier.value;
			var scale:Number = 1 / multiplier;
			workspace.scaleX = scale;
			workspace.scaleY = scale;
			workspace.width = workspace.parent.width * multiplier;
			workspace.height = workspace.parent.height * multiplier;
			handleScreenshotImageSize();
		}
	
		private function handleScreenshotImageSize():void
		{
			if (_screenshot)
			{
				if (WeaveAPI.ErrorManager.errors.length)
				{
					handleRemoveScreenshot();
					return;
				}
				_screenshot.width = this.width;
				_screenshot.height = this.height;
			}
		}
		
		private var adminService:LocalAsyncService = null;
		
		private const saveTimer:Timer = new Timer( 10000 );
		private static const RECOVER_SHARED_OBJECT:String = "WeaveAdminConsoleRecover";
		private function saveRecoverPoint(event:Event = null):void
		{
			if (detectLinkableObjectChange(saveRecoverPoint, WeaveAPI.globalHashMap))
			{
				var cookie:SharedObject = SharedObject.getLocal(RECOVER_SHARED_OBJECT);
				cookie.data[RECOVER_SHARED_OBJECT] = Weave.createWeaveFileContent();
				cookie.flush();
			}
		}
		private function getRecoverPoint():ByteArray
		{
			var cookie:SharedObject = SharedObject.getLocal(RECOVER_SHARED_OBJECT);
			return cookie.data[RECOVER_SHARED_OBJECT] as ByteArray;
		}
		
		private function saveSessionStateToServer():void
		{
			if (adminService == null)
			{
				Alert.show(lang("Not connected to Admin Console."), lang("Error"));
				return;
			}
			
			if (!Weave.fileName)
				Weave.fileName = getFlashVarFile().split("/").pop();
			
			ExportSessionStateOptions.openExportPanel(
				"Save session state to server",
				function(content:Object):void
				{
					addAsyncResponder(
						adminService.invokeAsyncMethod('saveWeaveFile', [content, Weave.fileName, true]),
						function(event:ResultEvent, fileName:String):void
						{
							Alert.show(String(event.result), lang("Admin Console Response"));
						},
						function(event:FaultEvent, fileName:String):void
						{
							reportError(event.fault, lang("Unable to connect to Admin Console"));
						},
						Weave.fileName
					);
				}
			);
		}
		
		// this function may be called by the Admin Console to close this window, needs to be public
		public function closeWeavePopup():void
		{
			ExternalInterface.call("window.close()");
		}

		/**
		 * Optional menu bar (bottom of screen) to control the collaboration service and interaction
		 * between users.
		 */
		private var _collabMenu:CollaborationMenuBar = null;
		
		private function toggleCollaborationMenuBar():void
		{
			if (!_collabMenu)
				_collabMenu = new CollaborationMenuBar();
			
			if( Weave.properties.enableCollaborationBar.value )
			{
				if( !_collabMenu.parent )
				{
					_collabMenu.percentWidth = 100;
					this.addChild(_collabMenu);
					_collabMenu.addedToStage();
				}
			} else {
				try
				{
					if( this == _collabMenu.parent ) {
						_collabMenu.dispose();
						this.removeChild(_collabMenu);
					}
					
				} catch( error:Error ) {
					reportError(error);
				}
			}
		}

		public function getMenuItems():ArrayCollection
		{
			return _weaveMenu.menubar.dataProvider as ArrayCollection;
		}
		
		/**
		 * This will be used to incorporate branding into any weave view.  Linkable to the Open Indicators Consortium website.
		 */
		private var _oicLogoPane:OICLogoPane = new OICLogoPane();
		
		/**
		 * Optional menu bar (top of the screen) and task bar (bottom of the screen).  These would be used for an advanced analyst
		 * view to add new tools, manage windows, do advanced tasks, etc.
		 */
		private var _weaveMenu:WeaveMenuBar = null;
		
		private function toggleMenuBar():void
		{
			if (!enabled)
			{
				callLater(toggleMenuBar);
				return;
			}
			
			if (!historySlider)
			{
				historySlider = EditorManager.getNewEditor(Weave.history) as UIComponent;
				if (historySlider)
					this.addChildAt(historySlider, this.getChildIndex(visDesktop));
				else
					reportError("Unable to get editor for SessionStateLog");
			}
			
			DraggablePanel.adminMode = adminService || getFlashVarEditable();
			if (Weave.properties.enableMenuBar.value || adminService || getFlashVarEditable())
			{
				if (!_weaveMenu)
				{
					_weaveMenu = new WeaveMenuBar();

					//trace("MENU BAR ADDED");
					_weaveMenu.percentWidth = 100;
					callLater(setupVisMenuItems);
					
					//PopUpManager.addPopUp(_weaveMenu, this);
					this.addChildAt(_weaveMenu, 0);
					
					if (this == _oicLogoPane.parent)
						this.removeChild(_oicLogoPane);
				}
				
				// always show menu bar when admin service is present
				if (historySlider)
					historySlider.alpha = _weaveMenu.alpha = Weave.properties.enableMenuBar.value ? 1.0 : 0.3;
			}
			// otherwise there is no menu bar, (which normally includes the oiclogopane, so add one to replace it)
			else
			{
				if (historySlider)
					historySlider.visible = historySlider.includeInLayout = false;
				try
				{
		   			if (_weaveMenu && this == _weaveMenu.parent)
						removeChild(_weaveMenu);

		   			_weaveMenu = null;
					
					if (Weave.properties.showCopyright.value)
					{
						addChild(_oicLogoPane);
					}
					else if (this == _oicLogoPane.parent)
						removeChild(_oicLogoPane);
				}
				catch(error:Error)
				{
					reportError(error);
				}
			}
		}
		
		private var _dataMenu:WeaveMenuItem  = null;
		private var _exportMenu:WeaveMenuItem  = null;
		private var _sessionMenu:WeaveMenuItem = null;
		private var _toolsMenu:WeaveMenuItem   = null;
		private var _windowMenu:WeaveMenuItem  = null;
		private var _selectionsMenu:WeaveMenuItem = null;
		private var _subsetsMenu:WeaveMenuItem = null;
		private var _aboutMenu:WeaveMenuItem   = null;

		private function setupVisMenuItems():void
		{
			setupContextMenu();
			
			if (!_weaveMenu)
				return;
			
			_weaveMenu.validateNow();
			
			_weaveMenu.removeAllMenus();
			
			if (Weave.properties.enableDataMenu.value)
			{
				_dataMenu = _weaveMenu.addMenuToMenuBar(lang("Data"), false);
				if (Weave.properties.enableLoadMyData.value)
				{
					_weaveMenu.addMenuItemToMenu(
						_dataMenu,
						new WeaveMenuItem(
							lang("Load my data"),
							function():void
							{
								WizardPanel.createWizard(_this, new NewUserWizard());
							}
						)
					);
				}
				
				if (Weave.properties.enableBrowseData.value)
				{
					_weaveMenu.addMenuItemToMenu(_dataMenu, new WeaveMenuItem(lang("Browse Data"), AttributeSelectorPanel.open));
				}
				
				if (Weave.properties.enableManageDataSources.value)
					_weaveMenu.addMenuItemToMenu(_dataMenu, new WeaveMenuItem(lang("Manage or browse data"), DraggablePanel.openStaticInstance, [DataSourceManager]));
				
				if (Weave.properties.enableRefreshHierarchies.value)
				{
					_weaveMenu.addMenuItemToMenu(_dataMenu,
						new WeaveMenuItem(lang("Refresh all data source hierarchies"),
							function ():void {
								var sources:Array = WeaveAPI.globalHashMap.getObjects(IDataSource);
								for each (var source:IDataSource in sources)
									source.refreshHierarchy();
							}
						)
					);
				}

				if (Weave.properties.enableExportCSV.value)
					_weaveMenu.addMenuItemToMenu(_dataMenu, new WeaveMenuItem(lang("Export CSV from all visualizations"), exportCSV));
			}
			
			
			if (Weave.properties.enableDynamicTools.value)
			{
				_toolsMenu = _weaveMenu.addMenuToMenuBar(lang("Tools"), false);


				createToolMenuItem(Weave.properties.showColorController, lang("Color Controller"), DraggablePanel.openStaticInstance, [ColorController]);
				createToolMenuItem(Weave.properties.showProbeToolTipEditor, lang("Edit Mouseover Info"), DraggablePanel.openStaticInstance, [ProbeToolTipEditor]);
				createToolMenuItem(Weave.properties.showProbeWindow, lang("Mouseover Window"), createGlobalObject, [ProbeToolTipWindow, "ProbeToolTipWindow"]);
				createToolMenuItem(Weave.properties.showEquationEditor, lang("Equation Column Editor"), DraggablePanel.openStaticInstance, [EquationEditor]);
				createToolMenuItem(Weave.properties.showCollaborationEditor, lang("Collaboration Settings"), DraggablePanel.openStaticInstance, [CollaborationEditor]);

				var _this:VisApplication = this;

				if (!Weave.properties.dashboardMode.value)
				{
					_weaveMenu.addSeparatorToMenu(_toolsMenu);
					
					for each (var impl:Class in WeaveAPI.getRegisteredImplementations(IVisTool))
					{
						if (Weave.properties.getToolToggle(impl).value)
						{
							var displayName:String = WeaveAPI.getRegisteredImplementationDisplayName(impl);
							_weaveMenu.addMenuItemToMenu(_toolsMenu, new WeaveMenuItem(lang("Add {0}", displayName), createGlobalObject, [impl]));
						}
					}
				}
				

				if (Weave.properties.enableWeaveAnalystMode.value)
				{
					var analystInstance:WeaveAnalyst = WeaveAnalyst.getInstance();
					this.visDesktop.addChild(analystInstance);
				}

				
				_weaveMenu.addSeparatorToMenu(_toolsMenu);
				_weaveMenu.addMenuItemToMenu(_toolsMenu, new WeaveMenuItem(
					function():String { return lang((Weave.properties.dashboardMode.value ? "Disable" : "Enable") + " dashboard mode"); },
					function():void { Weave.properties.dashboardMode.value = !Weave.properties.dashboardMode.value; }

				));
				
/*
				_weaveMenu.addMenuItemToMenu(_toolsMenu,new WeaveMenuItem(
					function():String { return lang((Weave.properties.weaveAnalystMode.value ? "Disable" : "Enable") + " Weave Analyst"); },
					function(): void { Weave.properties.weaveAnalystMode.value = !Weave.properties.weaveAnalystMode.value;}
					
				));
*/
			}
			
			if (Weave.properties.enableSelectionsMenu.value)
			{	
				_selectionsMenu = _weaveMenu.addMenuToMenuBar(lang("Selections"), true);
				setupSelectionsMenu();
			}
			
			if (Weave.properties.enableSubsetsMenu.value)
			{	
				_subsetsMenu = _weaveMenu.addMenuToMenuBar(lang("Subsets"), true);
				setupSubsetsMenu();
			}
			
			var showHistorySlider:Boolean = false;
			if (Weave.properties.enableSessionMenu.value || adminService)
			{
				_sessionMenu = _weaveMenu.addMenuToMenuBar(lang("Session"), false);
				_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem(lang("Edit session state"), SessionStateEditor.openDefaultEditor));
				_weaveMenu.addSeparatorToMenu(_sessionMenu);
				_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem(lang("Import session history"), handleImportSessionState));
				_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem(lang("Export session history"), ExportSessionStateOptions.openExportPanel));
				_weaveMenu.addSeparatorToMenu(_sessionMenu);
				_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem(
					function():String { return lang( (Weave.properties.showSessionHistoryControls.value ? "Hide" : "Show") + " session history controls" ); },
					function():void { Weave.properties.showSessionHistoryControls.value = !Weave.properties.showSessionHistoryControls.value; }
				));
				if (Weave.ALLOW_PLUGINS)
				{
					_weaveMenu.addSeparatorToMenu(_sessionMenu);
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem(lang("Manage plugins"), managePlugins));
				}
				_weaveMenu.addSeparatorToMenu(_sessionMenu);
				if (ExternalInterface.available)
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem(lang('Restart Weave'), Weave.externalReload));
				if (Weave.properties.showCollaborationMenuItem.value)
				{
					_weaveMenu.addSeparatorToMenu(_sessionMenu);
					_weaveMenu.addMenuItemToMenu(
						_sessionMenu,
						new WeaveMenuItem(
							function():String
							{
								var collabTool:CollaborationTool = CollaborationTool.instance;
								if (collabTool && collabTool.collabService.isConnected)
									return lang("Open collaboration window");
								else
									return lang("Connect to collaboration server");
							},
							DraggablePanel.openStaticInstance,
							[CollaborationTool]
						)
					);
				}
				if (adminService)
				{
					_weaveMenu.addSeparatorToMenu(_sessionMenu);
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem(
						lang("Save session state to server"),
						function():void { saveSessionStateToServer(); }
					));
				}
				
				showHistorySlider = Weave.properties.showSessionHistoryControls.value;
			}
			if (historySlider)
				historySlider.visible = historySlider.includeInLayout = showHistorySlider;
			
			if (Weave.properties.enableWindowMenu.value || adminService)
			{
				_windowMenu = _weaveMenu.addMenuToMenuBar(lang("Window"), true);
				setupWindowMenu();
			}
			
			if (Weave.properties.enableAboutMenu.value)
			{
				_aboutMenu = _weaveMenu.addMenuToMenuBar(lang("Help"), false);
				
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem(lang("Report a problem"), function ():void {
					navigateToURL(new URLRequest("http://info.oicweave.org/projects/weave/issues/new"), "_blank");
				}));
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem(lang("Visit {0}", "OICWeave.org"), function ():void {
					navigateToURL(new URLRequest("http://www.oicweave.org"), "_blank");
				}));
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem(lang("Visit Weave Wiki"), function ():void {
					navigateToURL(new URLRequest("http://info.oicweave.org/projects/weave/wiki"), "_blank");
				}));
				
				_weaveMenu.addSeparatorToMenu(_aboutMenu);
				
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem(lang("Weave version: {0}", Weave.properties.version.value)));
			}
		}
		
		private function createToolMenuItem(toggle:LinkableBoolean, title:String, callback:Function, params:Array = null):void
		{
			if (toggle.value)
				_weaveMenu.addMenuItemToMenu(_toolsMenu, new WeaveMenuItem(title, callback, params));
		}
		
		public function CSVWizardWithData(content:Object):void
		{
			var newUserWiz:NewUserWizard = new NewUserWizard();
			WizardPanel.createWizard(this, newUserWiz);
			newUserWiz.CSVFileDrop(content as ByteArray);
		}
		
		private var _screenshot:Image = null;
		private var _snapshotTimer:Timer = new Timer(1000);
		public function loadSessionState(fileContent:Object, fileName:String):void
		{
			DebugTimer.begin();
			try
			{
				if (getFlashVarRecover())
					fileContent = getRecoverPoint();
				// attempt to parse as a Weave archive
				if (fileContent)
				{
					Weave.loadWeaveFileContent(ByteArray(fileContent));
					if (_usingDeprecatedFlashVar)
						reportError(DEPRECATED_FLASH_VAR_MESSAGE);
				}
				Weave.fileName = fileName;
			}
			catch (error:Error)
			{
				// attempt to parse as xml
				var xml:XML = null;
				// check the first character because a non-xml string may still parse as a single xml text node.
				if (String(fileContent).charAt(0) == '<')
				{
					try
					{
						xml = XML(fileContent);
					}
					catch (xmlError:Error)
					{
						// invalid xml
						reportError(xmlError);
					}
				}
				else
				{
					// not an xml, so report the original error
					reportError(error);
				}
				
				if (xml)
				{
					// backwards compatibility:
					var stateStr:String = xml.toXMLString();
					while (stateStr.indexOf("org.openindicators") >= 0)
					{
						stateStr = stateStr.replace("org.openindicators", "weave");
						xml = XML(stateStr);
					}
					var tag:XML;
					for each (tag in xml.descendants("OpenIndicatorsServletDataSource"))
						tag.setLocalName("WeaveDataSource");
					for each (tag in xml.descendants("OpenIndicatorsDataSource"))
						tag.setLocalName("WeaveDataSource");
					for each (tag in xml.descendants("EmptyTool"))
						tag.setLocalName("CustomTool");
					for each (tag in xml.descendants("WMSPlotter2"))
						tag.setLocalName("WMSPlotter");
					for each (tag in xml.descendants("SessionedTextArea"))
					{
						tag.setLocalName("SessionedTextBox");
						tag.appendChild(<enableBorders>true</enableBorders>);
						tag.appendChild(<htmlText>{tag.textAreaString.text()}</htmlText>);
						tag.appendChild(<panelX>{tag.textAreaWindowX.text()}</panelX>);
						tag.appendChild(<panelY>{tag.textAreaWindowY.text()}</panelY>);
					}
					
					// add missing attribute titles
					for each (var hierarchy:XML in xml.descendants('hierarchy'))
					{
						for each (tag in hierarchy.descendants("attribute"))
						{
							if (!String(tag.@title))
							{
								var newTitle:String = String(tag.@csvColumn);
								if (!newTitle && String(tag.@name) && String(tag.@year))
									newTitle = String(tag.@name) + ' (' + tag.@year + ')';
								else if (String(tag.@name))
									newTitle = String(tag.@name);
								tag.@title = newTitle || 'untitled';
							}
						}
					}
					
					Weave.loadWeaveFileContent(xml);
					Weave.fileName = fileName;
					
//					// An empty subset is not of much use.  If the subset is empty, reset it to include all records.
//					var subset:KeyFilter = Weave.defaultSubsetKeyFilter;
//					if (subset.includeMissingKeys.value == false && subset.included.keys.length == 0 && subset.excluded.keys.length == 0)
//						subset.includeMissingKeys.value = true;
				}
			}
			DebugTimer.end('loadSessionState', fileName);
			var ssba:ByteArray = Weave.getScreenshotFromArchive();
			if (ssba)
			{
				_screenshot = new Image();
				_screenshot.source = ssba;
				_screenshot.maintainAspectRatio = false;
				_screenshot.smoothBitmapContent = true;
				handleScreenshotImageSize();
				if (_screenshot)
				{
					PopUpManager.addPopUp(_screenshot,this,false);
					PopUpManager.bringToFront(_screenshot);
					_snapshotTimer.addEventListener(TimerEvent.TIMER,handleSnapShotTimer);
					_snapshotTimer.start();
				}
			}
			callLater(toggleMenuBar);
			
			if (!getFlashVarAdminConnectionName())
				enabled = true;
			

			/*if (_weaveMenu && _toolsMenu)
			{
				var first:Boolean = true;
				//add reports to tools menu
				for each (var report:WeaveReport in WeaveAPI.globalHashMap.getObjects(WeaveReport))
				{
					if (first)
						_weaveMenu.addSeparatorToMenu(_toolsMenu);
					first = false;
					
					var reportMenuItem:WeaveMenuItem = new WeaveMenuItem(WeaveAPI.globalHashMap.getName(report), WeaveReport.requestReport, [report]);
					_weaveMenu.addMenuItemToMenu(_toolsMenu, reportMenuItem);
				}
			}*/
			
			// generate the context menu items
			setupContextMenu();

			// Set the name of the CSS style we will be using for this application.  If weaveStyle.css is present, the style for
			// this application can be defined outside the code in a CSS file.
			this.styleName = "application";	
		}
		
		private var fadeEffect:Fade = new Fade();
		private function handleSnapShotTimer(event:Event):void
		{
			if(WeaveAPI.ProgressIndicator.getNormalizedProgress() ==1)
			{
				fadeEffect.alphaFrom = _screenshot.alpha;
				fadeEffect.alphaTo = 0;
				fadeEffect.duration = 500;
				fadeEffect.target = _screenshot;
				fadeEffect.addEventListener(EffectEvent.EFFECT_END,handleRemoveScreenshot);
				fadeEffect.play();
			}
		}
		
		private function handleRemoveScreenshot(event:Event=null):void
		{
			if (_screenshot)
			{
				_snapshotTimer.stop();
				_snapshotTimer.removeEventListener(TimerEvent.TIMER,handleSnapShotTimer);
				PopUpManager.removePopUp(_screenshot);
				_screenshot = null;
			}
		}
		
		private function createGlobalObject(classDef:Class, name:String = null):*
		{
			var className:String = getQualifiedClassName(classDef).split("::")[1];

			if (name == null)
				name = WeaveAPI.globalHashMap.generateUniqueName(className);
			var object:* = WeaveAPI.globalHashMap.requestObject(name, classDef, false);
			
			// put panel in front
			WeaveAPI.globalHashMap.setNameOrder([name]);
			
			// open control panel for new tool
			var dp:DraggablePanel = object as DraggablePanel;
			if (dp.controlPanel)
				dp.callLater(handleDraggablePanelAdded, [dp]);
		}
		
		public function handleDraggablePanelAdded(dp:DraggablePanel):void
		{
			if (objectWasDisposed(dp) || !dp.parent)
				return;
			
			dp.validateNow();
			var b:Button = dp.userControlButton;
			var dpc:ICallbackCollection = getCallbackCollection(dp);
			
			var color:uint = 0x0C4785;//0x0b333c;
			var timeout:int = getTimer() + 1000 * 5;
			var tip:UIComponent = ToolTipManager.createToolTip(lang("Start here"), 0, 0, null, dp) as UIComponent;
			Weave.properties.panelTitleTextFormat.copyToStyle(tip);
			tip.setStyle('color', 0xFFFFFF);
			tip.setStyle('fontWeight', 'bold');
			tip.setStyle('borderStyle', "errorTipBelow");
			tip.setStyle("backgroundColor", color);
			tip.setStyle("borderColor", color);
			tip.setStyle('borderSkin', CustomToolTipBorder);
			var callback:Function = function():void {
				var p:Point = b.localToGlobal(new Point(0, b.height + 5));
				tip.move(int(p.x), int(p.y));
				tip.visible = !!b.parent;
				if (getTimer() > timeout)
					removeTip();
			};
			var removeTip:Function = function(..._):void {
				ToolTipManager.destroyToolTip(tip as IToolTip);
				WeaveAPI.StageUtils.removeEventCallback(Event.ENTER_FRAME, callback);
				dpc.removeCallback(removeTip);
				b.removeEventListener(MouseEvent.ROLL_OVER, removeTip);
			};
			b.addEventListener(MouseEvent.ROLL_OVER, removeTip);
			dpc.addDisposeCallback(null, removeTip);
			WeaveAPI.StageUtils.addEventCallback(Event.ENTER_FRAME, dp, callback, true);
			
		
			/*
			dp.toggleControlPanel();
			var coords:Point = dp.localToGlobal(new Point(64,64));
			if (dp.controlPanel.parent)
			{
				coords = dp.controlPanel.parent.globalToLocal(coords);
				dp.controlPanel.move(coords.x, coords.y);
			}
			*/
			
			/*
			var mapTool:MapTool = dp as MapTool;
			if (mapTool)
			{
				mapTool.toggleControlPanel();
				var plotter:GeometryPlotter = mapTool.visualization.plotManager.plotters.requestObject('geometry', GeometryPlotter, false);
				var geom:DynamicColumn = plotter.geometryColumn.internalDynamicColumn;
				AttributeSelectorPanel.openDefaultSelector(geom, lang("Geometry"));
			}
			*/
		}
		
		private function setupSelectionsMenu():void
		{
			if (_weaveMenu && _selectionsMenu)
				SelectionManager.setupMenu(_weaveMenu, _selectionsMenu);
		}
		private function setupSubsetsMenu():void
		{
			if (_weaveMenu && _subsetsMenu)
				SubsetManager.setupMenu(_weaveMenu, _subsetsMenu);
		}

		private function get topPanel():DraggablePanel
		{
			var children:Array = WeaveAPI.globalHashMap.getObjects(DraggablePanel);
			while (children.length)
			{
				var panel:DraggablePanel = children.pop() as DraggablePanel;
				if (panel.visible)
					return panel;
			}
			
			return null;
		}
		
		private function setupWindowMenu():void
		{
			if (!(_weaveMenu && _windowMenu && Weave.properties.enableWindowMenu.value))
				return;
			
			if (_windowMenu.children)
				_windowMenu.children.removeAll();
			
			if (Weave.properties.enableUserPreferences.value || adminService)
				_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(lang("Preferences"), DraggablePanel.openStaticInstance, [WeavePropertiesEditor]));
			
			_weaveMenu.addSeparatorToMenu(_windowMenu);

			var label:*;
			var click:Function;
			var enable:*;

			if (Weave.properties.enableFullScreen.value)
			{
				label = function():String {
					if ( stage && stage.displayState == StageDisplayState.FULL_SCREEN) 
						return lang('Exit Full-screen mode'); 
					
					return lang('Enter Full-screen mode');
				};
				click = function():void{
					if (stage && stage.displayState == StageDisplayState.NORMAL )
					{
						try
						{
							// set full screen display
							stage.displayState = StageDisplayState.FULL_SCREEN;
						}
						catch (e:Error)
						{
							Alert.show(lang("This website has not enabled full-screen mode, so this option will now be disabled."), lang("Full-screen mode not allowed"));
							Weave.properties.enableFullScreen.value = false;
						}
					}
					else if (stage)
					{
						// set normal display
						stage.displayState = StageDisplayState.NORMAL;
					}
				};
				_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(label, click, null, Weave.properties.enableFullScreen.value));
			}
			
			_weaveMenu.addSeparatorToMenu(_windowMenu);
			
			if (Weave.properties.enableTileAllWindows.value)
				_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(lang("Tile all windows"), DraggablePanel.tileWindows));
			if (Weave.properties.enableCascadeAllWindows.value)
				_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(lang("Cascade all windows"), DraggablePanel.cascadeWindows));
			
			_weaveMenu.addSeparatorToMenu(_windowMenu);

			if (Weave.properties.enableMinimizeAllWindows.value)
			{
				click = function():void {
					for each (panel in WeaveAPI.globalHashMap.getObjects(DraggablePanel))
						if (panel.minimizable.value && !panel.minimized.value)
							panel.minimizePanel();
				};
				enable = function():Boolean {
					for each (panel in WeaveAPI.globalHashMap.getObjects(DraggablePanel))
						if (panel.minimizable.value && !panel.minimized.value)
							return true;
					return false;
				};
				_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(lang("Minimize all windows"), click, null, enable));
			}
			
			if (Weave.properties.enableRestoreAllMinimizedWindows.value)
			{
				click = function():void {
					for each (panel in WeaveAPI.globalHashMap.getObjects(DraggablePanel))
						if (panel.minimized.value)
							panel.restorePanel();
				};
				enable = function():Boolean {
					for each (panel in WeaveAPI.globalHashMap.getObjects(DraggablePanel))
						if (panel.minimized.value)
							return true;
					return false;
				};
				_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(lang("Restore all minimized windows"), click, null, enable));
			}
			
			if (Weave.properties.enableCloseAllWindows.value)
			{
				click = function():void {
					for each (panel in WeaveAPI.globalHashMap.getObjects(DraggablePanel))
						if (panel.closeable.value)
							panel.removePanel();
				};
				enable = function():Boolean {
					for each (panel in WeaveAPI.globalHashMap.getObjects(DraggablePanel))
						if (panel.closeable.value)
							return true;
					return false;
				};
				_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(lang("Close all windows"), click, null, enable));
			}
			
			_weaveMenu.addSeparatorToMenu(_windowMenu);
			
			var panels:Array = WeaveAPI.globalHashMap.getObjects(DraggablePanel);
			for (var i:int = 0; i < panels.length; i++)
			{	
				var panel:DraggablePanel = panels[i] as DraggablePanel;
				var newToolMenuItem:WeaveMenuItem = createWindowMenuItem(panel, _weaveMenu, _windowMenu);
				if (_weaveMenu)
					_weaveMenu.addMenuItemToMenu(_windowMenu, newToolMenuItem);
			}
		}
		
		private function createWindowMenuItem(panel:DraggablePanel, destinationMenuBar:WeaveMenuBar, destinationMenuItem:WeaveMenuItem):WeaveMenuItem
		{
			var label:Function = function():String
			{
				var menuLabel:String = '';
				if (panel.title && panel.title.replace(" ", "").length > 0) 
					menuLabel = panel.title;
				else
					menuLabel = lang("Untitled Window");
				
				
				if (panel.minimized.value)
				{
					menuLabel = ">\t" + menuLabel;
				}
				
				return menuLabel;
			}
			var newToolMenuItem:WeaveMenuItem = new WeaveMenuItem(label, panel.restorePanel);
			 
			newToolMenuItem.type = WeaveMenuItem.TYPE_RADIO;
			newToolMenuItem.groupName = "activeWindows";
			newToolMenuItem.toggledFunction = function():Boolean {
				return newToolMenuItem.relevantItemPointer == topPanel;
			};
			newToolMenuItem.relevantItemPointer = panel;
			
			addEventListener(FlexEvent.REMOVE, function(e:Event):void {
				if(destinationMenuBar && destinationMenuItem)
					destinationMenuBar.removeMenuItemFromMenu(newToolMenuItem, destinationMenuItem);
			});
										
			return newToolMenuItem;
		}

		private var _printToolMenuItem:ContextMenuItem = null;
		
		/**
		 * This function creates the context menu for this application by getting context menus from each
		 * class that defines them 
		 *  
		 * @TODO generalize this better...
		 * 
		 * @author abaumann 
		 */
		private function setupContextMenu():void
		{ 
			//if (contextMenu == null)
				contextMenu = new ContextMenu();
			contextMenu.addEventListener(ContextMenuEvent.MENU_SELECT, handleContextMenuOpened);
			
			// Hide the default Flash menu
			try
			{
				contextMenu['hideBuiltInItems']();
			}
			catch (e:Error)
			{
			}
			
			CustomContextMenuManager.removeAllContextMenuItems();
			
			if (Weave.properties.enableRightClick.value)
			{
				// Add context menu item for selection related items (subset creation, etc)	
				if (Weave.properties.enableSubsetControls.value)
				{
					KeySetContextMenuItems.createContextMenuItems(this);
				}
				if (Weave.properties.enableMarker.value)
					SingleImagePlotterEditor.createContextMenuItems(this);
				
				if (Weave.properties.enableDrawCircle.value)
					CirclePlotterSettings.createContextMenuItems(this);
				
				if (Weave.properties.enableAnnotation.value)
					SessionedTextBox.createContextMenuItems(this);
				
				if (Weave.properties.enablePenTool.value)
					PenTool.createContextMenuItems(this);
				
				if (Weave.properties.enableExportToolImage.value)
				{
					// Add a listener to this destination context menu for when it is opened
					//contextMenu.addEventListener(ContextMenuEvent.MENU_SELECT, handleContextMenuOpened);
					
					// Create a context menu item for printing of a single tool with title and logo
					_panelPrintContextMenuItem = CustomContextMenuManager.createAndAddMenuItemToDestination(
						lang("Print/Export Image of {0}", '...'),
						this,
						function(event:ContextMenuEvent):void { printOrExportImage(_panelToExport); },
						"4 exportMenuItems"
					);
					// By default this menu item is disabled so that it does not show up unless we right click on a tool
					_panelPrintContextMenuItem.enabled = false;
				}
				
				if (Weave.properties.enableExportApplicationScreenshot.value)
					_printToolMenuItem = CustomContextMenuManager.createAndAddMenuItemToDestination(lang("Print/Export Application Image"), this, handleContextMenuItemSelect, "4 exportMenuItems");
				
				if (Weave.properties.enableExportCSV.value)
				{
					// Add a listener to this destination context menu for when it is opened
					//contextMenu.addEventListener(ContextMenuEvent.MENU_SELECT, handleContextMenuOpened);
					
					// Create a context menu item for printing of a single tool with title and logo
					_exportCSVContextMenuItem = CustomContextMenuManager.createAndAddMenuItemToDestination(
						lang("Export CSV"), 
						this,
						function(event:ContextMenuEvent):void { exportCSV(_panelToExport as IVisToolWithSelectableAttributes); },
						"4 exportMenuItems"
					);
				}
				
				// Add context menu items for handling search queries
				if (Weave.properties.enableSearchForRecord.value)
					SearchEngineUtils.createContextMenuItems(this);
				
				if (Weave.properties.dataInfoURL.value)
					addLinkContextMenuItem(lang("Show Information About This Dataset..."), Weave.properties.dataInfoURL.value);
				
			}
		}

		// Create the context menu items for exporting panel images.  
		private var _panelPrintContextMenuItem:ContextMenuItem = null;
		private  var _exportCSVContextMenuItem:ContextMenuItem = null;
		private var exportCSVfileRef:FileReference = new FileReference();	// CSV download file references
		public function exportCSV(tool:IVisToolWithSelectableAttributes = null):void
		{
			try
			{
				var fileName:String = tool
					? getQualifiedClassName(tool).split(':').pop()
					: "data-export";
				fileName = "Weave-" + fileName + ".csv";
				
				var attrs:Array = [];
				if (tool)
				{
					VectorUtils.flatten(tool.getSelectableAttributes(), attrs);
				}
				else
				{
					// get equation columns and color column
					VectorUtils.flatten(WeaveAPI.globalHashMap.getObjects(IAttributeColumn), attrs);
					// get probe columns
					VectorUtils.flatten(WeaveAPI.globalHashMap.getObjects(ILinkableHashMap), attrs);
					for each (tool in WeaveAPI.globalHashMap.getObjects(IVisToolWithSelectableAttributes))
						VectorUtils.flatten(tool.getSelectableAttributes(), attrs);
				}
				
				var csvString:String = ColumnUtils.generateTableCSV(attrs);
				if (!csvString)
				{
					reportError("No data to export");
					return;
				}
				
				exportCSVfileRef.save(csvString, fileName);
			}
			catch (e:Error)
			{
				reportError(e);
			}			
		}
		
		// Handler for when the context menu is opened.  In here we will keep track of what tool we were over when we right clicked so 
		// that we can export an image of just this tool.  We also change the text in the context menu item for exporting an image of 
		// this tool so it  says the name of the tool to export.
		private var _panelToExport:DraggablePanel = null;
		private function handleContextMenuOpened(event:ContextMenuEvent):void
		{
			// When the context menu is opened, save a pointer to the active tool, this is the tool we want to export an image of
			_panelToExport = DraggablePanel.activePanel;
			CustomContextMenuManager.activePanel = DraggablePanel.activePanel;
			
			if (_panelPrintContextMenuItem)
			{
				// If this tool is valid (we are over a tool), then we want this menu item enabled, otherwise don't allow users to choose it
				_panelPrintContextMenuItem.caption = lang("Print/Export Image of {0}", _panelToExport ? _panelToExport.title : "...");
				_panelPrintContextMenuItem.enabled = (_panelToExport != null);
			}
		}
		
		private var _weaveFileRef:FileReference = null;
		private function handleImportSessionState():void
		{
			try
			{
				if (!_weaveFileRef)
				{
					_weaveFileRef = new FileReference();
					_weaveFileRef.addEventListener(Event.SELECT,   function (e:Event):void { _weaveFileRef.load(); } );
					_weaveFileRef.addEventListener(Event.COMPLETE, function (e:Event):void { loadSessionState(e.target.data, _weaveFileRef.name); } );
				}
				_weaveFileRef.browse([new FileFilter(lang("Weave files"), "*.weave"),new FileFilter(lang("All files"), "*.*")]);
			}
			catch (e:Error)
			{
				reportError(e);
			}
		}
		
		private function managePlugins():void
		{
			var popup:AlertTextBox;
			popup = PopUpManager.createPopUp(this, AlertTextBox) as AlertTextBox;
			popup.allowEmptyInput = true;
			popup.textInput = WeaveAPI.CSVParser.createCSVRow(Weave.getPluginList());
			popup.title = lang("Specify which plugins to load");
			popup.message = lang("List plugin .SWC files, separated by commas. Weave will reload itself if plugins have to be unloaded.");
			popup.addEventListener(AlertTextBoxEvent.BUTTON_CLICKED, handlePluginsChange);
			PopUpManager.centerPopUp(popup);
		}
		
		private function handlePluginsChange(event:AlertTextBoxEvent):void
		{
			if (event.confirm)
			{
				var plugins:Array = WeaveAPI.CSVParser.parseCSVRow(event.textInput) || [];
				Weave.setPluginList(plugins, null);
			}
		}
		
		public function printOrExportImage(component:UIComponent):void
		{
			if (!component)
				return;
			
			//initialize the print format
			var printPopUp:PrintPanel = new PrintPanel();
   			PopUpManager.addPopUp(printPopUp, WeaveAPI.topLevelApplication as UIComponent, true);
   			PopUpManager.centerPopUp(printPopUp);
   			//add current snapshot to Print Format
			printPopUp.componentToScreenshot = component;
		}

		/**
		 * Update the page title.
		 */
		private function updatePageTitle():void
		{
			try
			{
				if (ExternalInterface.available)
					ExternalInterface.call("setTitle", Weave.properties.pageTitle.value);
			}
			catch (e:Error)
			{
				reportError(e);
			}
		}
		
		/** 
		 * Add a context menu item that goes to an associated url in a new browser window/tab
		 */
		private function addLinkContextMenuItem(text:String, url:String, separatorBefore:Boolean=false):void
		{
			CustomContextMenuManager.createAndAddMenuItemToDestination(text, 
															  this, 
                                                              function(e:Event):void { navigateToURL(new URLRequest(url), "_blank"); },
                                                              "4 linkMenuItems");	
		}

		/**
		 * @TODO This should be removed -- ideally VisApplication has no context menu items itself, only other classes do
		 */
		protected function handleContextMenuItemSelect(event:ContextMenuEvent):void
		{
			if (event.currentTarget == _printToolMenuItem)
   			{
   				printOrExportImage(visDesktop.workspace);
   			}
   			
		}
	}
}
