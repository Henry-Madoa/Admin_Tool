/// <summary>
/// Codeunit License Mgt. (ID 50101).
/// </summary>
codeunit 50111 "License Mgt."
{
    procedure ImportLicense()
    var
        ActiveSession: Record "Active Session";
        TempBlob: Codeunit "Temp Blob";
        FileMgt: Codeunit "File Management";
        Window: Dialog;
        Powershellrunner: DotNet _PowerShellRunner;
        AllFilesFilterTxt: Label '*.*';
        BusyDlg: Label 'Busy importing......';
        FileFilter: Label 'License (*.flf)|*.flf|All Files (*.*)|*.*';
        NAVAdminTool: Label 'NavAdminTool.ps1';
        CancelledErr: Label 'Operation cancelled by user.';
        SelectFileTxt: Label 'Select License File';
        FileName: Text;
    begin
        FileName := FileMgt.BLOBImportWithFilter(TempBlob, SelectFileTxt, '', FileFilter, AllFilesFilterTxt);

        if FileName = '' then
            Error(CancelledErr);

        FileName := TemporaryPath + FileName;

        if Exists(FileName) then
            Erase(FileName);

        FileMgt.BLOBExportToServerFile(TempBlob, FileName);
        ActiveSession.Get(ServiceInstanceId(), SessionId());

        PowerShellRunner := PowerShellRunner.CreateInSandbox;
        PowerShellRunner.WriteEventOnError := true;
        PowerShellRunner.ImportModule(ApplicationPath + NAVAdminTool);
        PowerShellRunner.AddCommand('Import-NAVServerLicense');
        Powershellrunner.AddParameter('ServerInstance', ActiveSession."Server Instance Name");
        PowerShellRunner.AddParameter('LicenseFile', FileName);
        PowerShellRunner.BeginInvoke;

        Window.Open(BusyDlg);

        while not PowerShellRunner.IsCompleted do
            Sleep(1000);

        Window.Close();
    end;


}