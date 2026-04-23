using System;
using System.IO;
using Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK;
using Microsoft.PowerPlatform.PowerAutomate.Desktop.Actions.SDK.Attributes;

namespace Modules.SampleActions
{
    [Action(Id = "LogEventToFile", Order = 1, Category = "Logging",
        FriendlyName = "Log Event To File",
        Description = "Appends a log message to the specified text file.")]
    [Throws("LogEventError")]
    public class LogEventToFile : ActionBase
    {
        [InputArgument(FriendlyName = "Log File Name",
            Description = "The full path to the log file where the message will be appended.")]
        public string LogFileName { get; set; }

        [InputArgument(FriendlyName = "Log Message",
            Description = "The message text to write to the log file.")]
        public string LogMessage { get; set; }

        [OutputArgument(FriendlyName = "Status Code",
            Description = "Returns True if the log entry was written successfully, False otherwise.")]
        public bool StatusCode { get; set; }

        public override void Execute(ActionContext context)
        {
            try
            {
                File.AppendAllText(LogFileName, LogMessage + Environment.NewLine);
                StatusCode = true;
            }
            catch (Exception e)
            {
                if (e is ActionException) throw;

                throw new ActionException("LogEventError", e.Message, e.InnerException);
            }
        }
    }
}
