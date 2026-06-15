import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Application entry point for the Autumn watch face.
class AutumnApp extends Application.AppBase {

    private var mView as AutumnView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Re-read settings and repaint when the user changes app settings
    // (Connect IQ app store / Garmin Connect mobile).
    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.loadSettings();
        }
        WatchUi.requestUpdate();
    }

    // Return the initial view of the watch face.
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        mView = new AutumnView();
        return [ mView ];
    }
}

function getApp() as AutumnApp {
    return Application.getApp() as AutumnApp;
}
