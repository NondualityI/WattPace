import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class TestApp extends Application.AppBase {
    
    private var myView as TestView?;

    function initialize() {
        AppBase.initialize();
    }

    // Matches Garmin's official multi-type return requirement
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new TestView();
        myView = view;
        return [ view ] as [WatchUi.Views];
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    // Triggers instantly whenever a user modifies settings on their app
    function onSettingsChanged() as Void {
        if (myView != null) {
            myView.loadUserSettings(); 
            WatchUi.requestUpdate(); // Instantly redraws the watch screen with the new numbers  
        }
    }
}

// Global helper function required by newer Connect IQ SDK targets - fetch app object correctly
function getApp() as TestApp {
    return Application.getApp() as TestApp;
}
