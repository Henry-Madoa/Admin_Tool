codeunit 50110 "Admin Tool Mgt."
{
    Permissions = TableData "17" = IMD, Tabledata "36" = IMD, Tabledata "37" = IMD, Tabledata "38" = IMD,
    Tabledata "39" = IMD, Tabledata "81" = IMD, Tabledata "21" = IMD, Tabledata "25" = IMD, Tabledata "32" = IMD,
    Tabledata "110" = IMD, TableData "111" = IMD, TableData "112" = IMD, TableData "113" = IMD, TableData "114" = IMD,
    TableData "115" = IMD, TableData "120" = IMD, Tabledata "121" = IMD, Tabledata "122" = IMD, Tabledata "123" = IMD,
     Tabledata "124" = IMD, Tabledata "125" = IMD, Tabledata "169" = IMD, Tabledata "379" = IMD, Tabledata "380" = IMD,
     Tabledata "271" = IMD, Tabledata "5802" = IMD, tabledata "6650" = IMD, tabledata "6660" = IMD, tabledata "6703" = IMD,
    tabledata "6701" = IMD;

    var
        CancelledByUserErr: Label 'The operation was cancelled by the user.';

    procedure CalcRecordsInTable(TableNoToCheck: Integer): Integer
    var
        FieldRec: Record Field;
        RecRef: RecordRef;
        NoOfRecords: Integer;
    begin
        FieldRec.SetRange(TableNo, TableNoToCheck);
        if FieldRec.FindFirst() then begin
            RecRef.Open(TableNoToCheck);
            RecRef.LockTable();
            NoOfRecords := RecRef.Count();
            RecRef.Close();
            exit(NoOfRecords);
        end;
        exit(0);
    end;

    procedure CheckTableRelations();
    var
        Field: Record Field;
        Field2: Record Field;
        KeyRec: Record "Key";
        RecordDeletion: Record "Record Deletion";
        RecordDeletionRelError: Record "Record Deletion Rel. Error";
        TableMetadata: Record "Table Metadata";
        RecRef: RecordRef;
        RecRef2: RecordRef;
        FieldRef: FieldRef;
        FieldRef2: FieldRef;
        SkipCheck: Boolean;
        Window: Dialog;
        EntryNo: Integer;
        NotExistsTxt: Label '%1 => %2 = ''%3'' does not exist in the ''%4'' table';
        CheckingRelationsTxt: Label 'Checking Relations Between Records!\Table: #1#######', Comment = '%1 = Table ID';
        CheckRelationsQst: Label 'Check Table Relations?';
    begin
        if not Confirm(CheckRelationsQst, false) then
            exit;

        Window.OPEN(CheckingRelationsTxt);

        RecordDeletionRelError.DeleteAll();

        if RecordDeletion.FindSet() then
            repeat
                Window.Update(1, Format(RecordDeletion."Table ID"));
                // Only allow "normal" tables to avoid errors, Skip TableType MicrosoftGraph and CRM etc.
                TableMetadata.SetRange(ID, RecordDeletion."Table ID");
                TableMetadata.SetRange(TableType, TableMetadata.TableType::Normal);
                if not TableMetadata.IsEmpty then begin
                    RecRef.OPEN(RecordDeletion."Table ID");
                    if RecRef.FindSet() then
                        repeat
                            field.SetRange(TableNo, RecordDeletion."Table ID");
                            field.SetRange(Class, field.Class::Normal);
                            field.SetFilter(RelationTableNo, '<>0');
                            if field.FindSet() then
                                repeat
                                    FieldRef := RecRef.field(field."No.");
                                    if (Format(FieldRef.VALUE) <> '') and (FORMAT(FieldRef.VALUE) <> '0') then begin
                                        RecRef2.OPEN(field.RelationTableNo);
                                        SkipCheck := false;
                                        if field.RelationFieldNo <> 0 then begin
                                            FieldRef2 := RecRef2.field(field.RelationFieldNo)
                                        end else begin
                                            KeyRec.Get(field.RelationTableNo, 1);  // PK
                                            Field2.SetRange(TableNo, field.RelationTableNo);
                                            Field2.SetFilter(FieldName, CopyStr(KeyRec.Key, 1, 30));
                                            if Field2.FindFirst() then // No Match if Dual PK
                                                FieldRef2 := RecRef2.field(Field2."No.")
                                            else
                                                SkipCheck := true;
                                        end;
                                        if (FieldRef.TYPE = FieldRef2.TYPE) and (FieldRef.LENGTH = FieldRef2.LENGTH) and (not SkipCheck) then begin
                                            FieldRef2.SetRange(FieldRef.VALUE);
                                            if not RecRef2.FindFirst() then begin
                                                RecordDeletionRelError.SetRange("Table ID", RecRef.NUMBER);
                                                if RecordDeletionRelError.FindLast() then
                                                    EntryNo := RecordDeletionRelError."Entry No." + 1
                                                else
                                                    EntryNo := 1;
                                                RecordDeletionRelError.Init();
                                                RecordDeletionRelError."Table ID" := RecRef.NUMBER;
                                                RecordDeletionRelError."Entry No." := EntryNo;
                                                RecordDeletionRelError."Field No." := FieldRef.NUMBER;
                                                RecordDeletionRelError.Error := CopyStr(StrSubstNo(NotExistsTxt, Format(RecRef.GETPOSITION()), Format(FieldRef2.NAME), Format(FieldRef.VALUE), Format(RecRef2.NAME)), 1, 250);
                                                RecordDeletionRelError.Insert();
                                            end;
                                        end;
                                        RecRef2.Close();
                                    end;
                                until field.Next() = 0;
                        until RecRef.Next() = 0;
                    RecRef.Close();
                end;
            until RecordDeletion.Next() = 0;
        Window.Close();
    end;

    procedure ClearRecordsToDelete();
    var
        RecordDeletion: Record "Record Deletion";
    begin
        RecordDeletion.ModifyAll("Delete Records", false);
    end;

    procedure DeleteRecords();
    var
        RecordDeletion: Record "Record Deletion";
        RecordDeletionRelError: Record "Record Deletion Rel. Error";
        RecRef: RecordRef;
        RunTrigger: Boolean;
        Window: Dialog;
        Selection: Integer;
        DeleteRecordsQst: Label '%1 table(s) were marked for deletion. All records in these tables will be deleted. Continue?';
        Options: Label 'Delete records without deletion trigger: Record.Delete(false),Delete records with deletion trigger: Record.Delete(true)';
        DeletingRecordsTxt: Label 'Deleting Records!\Table: #1#######', Comment = '%1 = Table ID';
        DeletionSuccessMsg: Label 'The records from %1 table(s) were succesfully deleted.';
        NoRecsFoundErr: Label 'No tables were marked for deletion. Please make sure that you check the field %1 in the tables where you want to delete records before you run this operation.';
    begin
        Selection := StrMenu(Options, 1);
        case Selection of
            0: // Cancelled
                Error(CancelledByUserErr);
            1: // Without trigger
                Clear(Runtrigger);
            2: // With trigger
                RunTrigger := true;
        end;

        Window.Open(DeletingRecordsTxt);

        RecordDeletion.SetRange("Delete Records", true);

        if RecordDeletion.Count() = 0 then
            Error(StrSubstNo(NoRecsFoundErr, RecordDeletion.FieldCaption("Delete Records")));

        if not Confirm(StrSubstNo(DeleteRecordsQst, RecordDeletion.Count()), false) then
            Error(CancelledByUserErr);

        if RecordDeletion.FindSet() then
            repeat
                Window.Update(1, Format(RecordDeletion."Table ID"));
                RecRef.OPEN(RecordDeletion."Table ID");
                RecRef.DeleteAll(RunTrigger);
                RecRef.Close();
                RecordDeletionRelError.SetRange("Table ID", RecordDeletion."Table ID");
                RecordDeletionRelError.DeleteAll();
            until RecordDeletion.Next() = 0;


        Window.Close();
        Message(StrSubstNo(DeletionSuccessMsg, RecordDeletion.Count()));
    end;

    procedure InsertUpdateTables();
    var
        AllObjWithCaption: Record AllObjWithCaption;
        RecordDeletion: Record "Record Deletion";
    begin
        AllObjWithCaption.SetRange("Object Type", AllObjWithCaption."Object Type"::Table);
        // Do not include system tables
        AllObjWithCaption.SetFilter("Object ID", '< %1', 2000000001);
        if AllObjWithCaption.FindSet() then
            repeat
                RecordDeletion.Init();
                RecordDeletion."Table ID" := AllObjWithCaption."Object ID";
                RecordDeletion.Company := CompanyName;
                if RecordDeletion.Insert() then;
            until AllObjWithCaption.Next() = 0;

    end;

    procedure SetSuggestedTable(TableID: Integer);
    var
        RecordDeletion: Record "Record Deletion";
    begin
        if RecordDeletion.Get(TableID) then begin
            RecordDeletion."Delete Records" := true;
            RecordDeletion.Modify();
        end;
    end;

    procedure SuggestRecordsToDelete();
    var
        Selection: Integer;
        Options: Label 'Suggest all transactional records to delete,Suggest unlicensed partner or custom records to delete';
    begin
        Selection := StrMenu(Options, 1);
        case Selection of
            0: // Cancelled
                Error(CancelledByUserErr);
            1: // Transactional
                SuggestTransactionalRecordsToDelete();
            2: // Unlicensed
                SuggestUnlicensedPartnerOrCustomRecordsToDelete();
        end;
    end;

    procedure SuggestUnlicensedPartnerOrCustomRecordsToDelete();
    var
        RecordDeletion: Record "Record Deletion";
        RecsSuggestedCount: Integer;
        RecordsSuggestedMsg: Label '%1 unlicensed partner or custom records were suggested.', Comment = '%1 number of unlicensed records';
    begin
        RecordDeletion.SetFilter("Table ID", '> %1', 49999);
        if RecordDeletion.FindSet(false) then
            repeat
                if not IsRecordStandardTable(RecordDeletion."Table ID") then
                    if not IsRecordInLicense(RecordDeletion."Table ID") then begin
                        SetSuggestedTable(RecordDeletion."Table ID");
                        RecsSuggestedCount += 1;
                    end;
            until RecordDeletion.Next() = 0;

        Message(RecordsSuggestedMsg, RecsSuggestedCount);
    end;

    procedure ViewRecords(RecordDeletion: Record "Record Deletion");
    begin
        Hyperlink(GetUrl(ClientType::Current, CompanyName, ObjectType::Table, RecordDeletion."Table ID"));
    end;

    local procedure IsRecordInLicense(TableID: Integer): Boolean
    var
        LicensePermission: Record "License Permission";
    begin
        // LicensePermission.Get(LicensePermission."Object Type"::Table, TableID);
        LicensePermission.Get(LicensePermission."Object Type"::TableData, TableID);
        if (LicensePermission."Read Permission" = LicensePermission."Read Permission"::" ") and
            (LicensePermission."Insert Permission" = LicensePermission."Insert Permission"::" ") and
            (LicensePermission."Modify Permission" = LicensePermission."Modify Permission"::" ") and
            (LicensePermission."Delete Permission" = LicensePermission."Delete Permission"::" ") and
            (LicensePermission."Execute Permission" = LicensePermission."Execute Permission"::" ")
        then
            exit(false)
        else
            exit(true);
    end;

    local procedure IsRecordStandardTable(TableID: Integer): Boolean
    begin
        case true of
            //5005270 - 5005363
            //(TableID >= Database::"Delivery Reminder Header") and (TableID <= Database::"Phys. Invt. Diff. List Buffer"):
            (TableID >= 52121423) and (TableID <= 52122999):
                exit(true);
            //99000750 - 99008535
            (TableID >= Database::"Work Shift") and (TableID <= Database::"Order Promising Line"):
                exit(true);
            // Microsoft Localizations
            (TableID >= 100000) and (TableID <= 999999):
                exit(true);
        end;
        exit(false);
    end;

    procedure OpenTable(TableId: Integer)
    var
        WebUrl: Text;
    begin
        WebUrl := StrSubstNo('%1&table=%2', System.GetUrl(ClientType::Web), TableId);
        Hyperlink(WebUrl);
    end;

    local procedure SuggestTransactionalRecordsToDelete()
    var
        RecordDeletion: Record "Record Deletion";
        AfterSuggestionDeleteCount: Integer;
        BeforeSuggestionDeleteCount: Integer;
        RecordsWereSuggestedMsg: Label '%1 records to delete were suggested.', Comment = '%1 = number of suggested records';
    begin
        RecordDeletion.SetRange("Delete Records", true);
        BeforeSuggestionDeleteCount := RecordDeletion.Count();
        SetSuggestedTable(Database::"Customer Price Group");
        SetSuggestedTable(Database::"Standard Text");
        SetSuggestedTable(Database::"Salesperson/Purchaser");
        SetSuggestedTable(Database::Location);
        SetSuggestedTable(Database::"G/L Account");
        SetSuggestedTable(Database::"G/L Entry");
        SetSuggestedTable(Database::Customer);
        SetSuggestedTable(Database::"Cust. Invoice Disc.");
        SetSuggestedTable(Database::"Cust. Ledger Entry");
        SetSuggestedTable(Database::Vendor);
        SetSuggestedTable(Database::"Vendor Invoice Disc.");
        SetSuggestedTable(Database::"Vendor Ledger Entry");
        SetSuggestedTable(Database::Item);
        SetSuggestedTable(Database::"Item Translation");
        SetSuggestedTable(Database::"Item Ledger Entry");
        SetSuggestedTable(Database::"Sales Header");
        SetSuggestedTable(Database::"Sales Line");
        SetSuggestedTable(Database::"Purchase Header");
        SetSuggestedTable(Database::"Purchase Line");
        SetSuggestedTable(Database::"Purch. Comment Line");
        SetSuggestedTable(Database::"Sales Comment Line");
        SetSuggestedTable(Database::"G/L Register");
        SetSuggestedTable(Database::"Item Register");
        SetSuggestedTable(Database::"Aging Band Buffer");
        SetSuggestedTable(Database::"Invt. Posting Buffer");
        SetSuggestedTable(Database::"Accounting Period");
        SetSuggestedTable(Database::"Account Use Buffer");
        SetSuggestedTable(Database::"Gen. Journal Template");
        SetSuggestedTable(Database::"Gen. Journal Line");
        SetSuggestedTable(Database::"Item Journal Template");
        SetSuggestedTable(Database::"Item Journal Line");
        SetSuggestedTable(Database::"BOM Component");
        SetSuggestedTable(Database::"Customer Posting Group");
        SetSuggestedTable(Database::"Vendor Posting Group");
        SetSuggestedTable(Database::"Inventory Posting Group");
        SetSuggestedTable(Database::"G/L Budget Name");
        SetSuggestedTable(Database::"G/L Budget Entry");
        SetSuggestedTable(Database::"Comment Line");
        SetSuggestedTable(Database::"Item Vendor");
        SetSuggestedTable(Database::"Sales Shipment Header");
        SetSuggestedTable(Database::"Sales Shipment Line");
        SetSuggestedTable(Database::"Sales Invoice Header");
        SetSuggestedTable(Database::"Sales Invoice Line");
        SetSuggestedTable(Database::"Sales Cr.Memo Header");
        SetSuggestedTable(Database::"Sales Cr.Memo Line");
        SetSuggestedTable(Database::"Purch. Rcpt. Header");
        SetSuggestedTable(Database::"Purch. Rcpt. Line");
        SetSuggestedTable(Database::"Purch. Inv. Header");
        SetSuggestedTable(Database::"Purch. Inv. Line");
        SetSuggestedTable(Database::"Purch. Cr. Memo Hdr.");
        SetSuggestedTable(Database::"Purch. Cr. Memo Line");
        SetSuggestedTable(Database::"Incoming Document");
        SetSuggestedTable(Database::"Incoming Document Approver");
        SetSuggestedTable(Database::"Incoming Document Attachment");
        SetSuggestedTable(Database::"Posted Docs. With No Inc. Buf.");
        SetSuggestedTable(Database::"Posted Docs. With No Inc. Buf.");
        SetSuggestedTable(Database::"ECSL VAT Report Line Relation");
        SetSuggestedTable(Database::"Resource Group");
        SetSuggestedTable(Database::Resource);
        SetSuggestedTable(Database::"Res. Capacity Entry");
        SetSuggestedTable(Database::Job);
        SetSuggestedTable(Database::"Job Ledger Entry");
        SetSuggestedTable(Database::"Standard Sales Code");
        SetSuggestedTable(Database::"Standard Sales Line");
        SetSuggestedTable(Database::"Standard Customer Sales Code");
        SetSuggestedTable(Database::"Standard Purchase Code");
        SetSuggestedTable(Database::"Standard Purchase Line");
        SetSuggestedTable(Database::"Standard Vendor Purchase Code");
        SetSuggestedTable(Database::"Reversal Entry");
        SetSuggestedTable(Database::"G/L Account Where-Used");
        SetSuggestedTable(Database::"Acc. Sched. KPI Buffer");
        SetSuggestedTable(Database::"Work Type");
        SetSuggestedTable(Database::"Res. Ledger Entry");
        SetSuggestedTable(Database::"Res. Journal Template");
        SetSuggestedTable(Database::"Res. Journal Line");
        SetSuggestedTable(Database::"Job Journal Template");
        SetSuggestedTable(Database::"Job Journal Line");
        SetSuggestedTable(Database::"Job Posting Group");
        SetSuggestedTable(Database::"Job Posting Buffer");
        SetSuggestedTable(Database::"Business Unit");
        SetSuggestedTable(Database::"Gen. Jnl. Allocation");
        SetSuggestedTable(Database::"Ship-to Address");
        SetSuggestedTable(Database::"Drop Shpt. Post. Buffer");
        SetSuggestedTable(Database::"Order Address");
        SetSuggestedTable(Database::"Post Code");
        SetSuggestedTable(Database::"Reason Code");
        SetSuggestedTable(Database::"Gen. Journal Batch");
        SetSuggestedTable(Database::"Item Journal Batch");
        SetSuggestedTable(Database::"Res. Journal Batch");
        SetSuggestedTable(Database::"Job Journal Batch");
        SetSuggestedTable(Database::"Resource Register");
        SetSuggestedTable(Database::"Job Register");
        SetSuggestedTable(Database::"Req. Wksh. Template");
        SetSuggestedTable(Database::"Requisition Wksh. Name");
        SetSuggestedTable(Database::"Requisition Line");
        SetSuggestedTable(Database::"VAT Reg. No. Srv Config");
        SetSuggestedTable(Database::"VAT Registration Log");
        SetSuggestedTable(Database::"Gen. Business Posting Group");
        SetSuggestedTable(Database::"Gen. Product Posting Group");
        SetSuggestedTable(Database::"General Posting Setup");
        SetSuggestedTable(Database::"G/L Entry - VAT Entry Link");
        SetSuggestedTable(Database::"VAT Entry");
        SetSuggestedTable(Database::"Transaction Type");
        SetSuggestedTable(Database::"Transport Method");
        SetSuggestedTable(Database::"Document Entry");
        SetSuggestedTable(Database::"VAT Statement Template");
        SetSuggestedTable(Database::"VAT Statement Line");
        SetSuggestedTable(Database::"VAT Statement Name");
        SetSuggestedTable(Database::"Tariff Number");
        SetSuggestedTable(Database::"Intrastat Jnl. Template");
        SetSuggestedTable(Database::"Intrastat Jnl. Batch");
        SetSuggestedTable(Database::"Intrastat Jnl. Line");
        SetSuggestedTable(Database::"Currency Amount");
        SetSuggestedTable(Database::"Customer Amount");
        SetSuggestedTable(Database::"Vendor Amount");
        SetSuggestedTable(Database::"Item Amount");
        SetSuggestedTable(Database::"Bank Account");
        SetSuggestedTable(Database::"Bank Account Ledger Entry");
        SetSuggestedTable(Database::"Check Ledger Entry");
        SetSuggestedTable(Database::"Bank Acc. Reconciliation");
        SetSuggestedTable(Database::"Bank Acc. Reconciliation Line");
        SetSuggestedTable(Database::"Bank Account Statement");
        SetSuggestedTable(Database::"Bank Account Statement Line");
        SetSuggestedTable(Database::"Bank Account Posting Group");
        SetSuggestedTable(Database::"Job Journal Quantity");
        SetSuggestedTable(Database::"Extended Text Header");
        SetSuggestedTable(Database::"Extended Text Line");
        SetSuggestedTable(Database::"Phys. Inventory Ledger Entry");
        SetSuggestedTable(Database::"Entry/Exit Point");
        SetSuggestedTable(Database::"Line Number Buffer");
        SetSuggestedTable(Database::"Transaction Specification");
        SetSuggestedTable(Database::Territory);
        SetSuggestedTable(Database::"Customer Bank Account");
        SetSuggestedTable(Database::"Vendor Bank Account");
        SetSuggestedTable(Database::"Payment Method");
        SetSuggestedTable(Database::"VAT Amount Line");
        SetSuggestedTable(Database::"Shipping Agent");
        SetSuggestedTable(Database::"Reminder Terms");
        SetSuggestedTable(Database::"Reminder Level");
        SetSuggestedTable(Database::"Reminder Text");
        SetSuggestedTable(Database::"Reminder Header");
        SetSuggestedTable(Database::"Reminder Line");
        SetSuggestedTable(Database::"Issued Reminder Header");
        SetSuggestedTable(Database::"Issued Reminder Line");
        SetSuggestedTable(Database::"Reminder Comment Line");
        SetSuggestedTable(Database::"Reminder/Fin. Charge Entry");
        SetSuggestedTable(Database::"Finance Charge Text");
        SetSuggestedTable(Database::"Finance Charge Memo Header");
        SetSuggestedTable(Database::"Finance Charge Memo Line");
        SetSuggestedTable(Database::"Issued Fin. Charge Memo Header");
        SetSuggestedTable(Database::"Issued Fin. Charge Memo Line");
        SetSuggestedTable(Database::"Fin. Charge Comment Line");
        SetSuggestedTable(Database::"Tax Area Translation");
        SetSuggestedTable(Database::"Payable Vendor Ledger Entry");
        SetSuggestedTable(Database::"Tax Area");
        SetSuggestedTable(Database::"Tax Area Line");
        SetSuggestedTable(Database::"Tax Jurisdiction");
        SetSuggestedTable(Database::"Tax Group");
        SetSuggestedTable(Database::"Tax Detail");
        SetSuggestedTable(Database::"VAT Business Posting Group");
        SetSuggestedTable(Database::"VAT Product Posting Group");
        SetSuggestedTable(Database::"VAT Posting Setup");
        SetSuggestedTable(Database::"Tax Jurisdiction Translation");
        SetSuggestedTable(Database::"Currency for Fin. Charge Terms");
        SetSuggestedTable(Database::"Currency for Reminder Level");
        SetSuggestedTable(Database::"Currency Exchange Rate");
        SetSuggestedTable(Database::"Adjust Exchange Rate Buffer");
        SetSuggestedTable(Database::"Currency Total Buffer");
        SetSuggestedTable(Database::"Tracking Specification");
        SetSuggestedTable(Database::"Reservation Entry");
        SetSuggestedTable(Database::"Entry Summary");
        SetSuggestedTable(Database::"Item Application Entry");
        SetSuggestedTable(Database::"Customer Discount Group");
        SetSuggestedTable(Database::"Item Discount Group");
        SetSuggestedTable(Database::"Item Application Entry History");
        SetSuggestedTable(Database::"Dimension Code Buffer");
        SetSuggestedTable(Database::"Close Income Statement Buffer");
        SetSuggestedTable(Database::"Dimension");
        SetSuggestedTable(Database::"Dimension Value");
        SetSuggestedTable(Database::"Dimension Combination");
        SetSuggestedTable(Database::"Dimension Value Combination");
        SetSuggestedTable(Database::"Default Dimension");
        SetSuggestedTable(Database::"Dimension ID Buffer");
        SetSuggestedTable(Database::"Default Dimension Priority");
        SetSuggestedTable(Database::"Dimension Set ID Filter Line");
        SetSuggestedTable(Database::"Dimension Buffer");
        SetSuggestedTable(Database::"ECSL VAT Report Line");
        SetSuggestedTable(Database::"Analysis View");
        SetSuggestedTable(Database::"Analysis View Filter");
        SetSuggestedTable(Database::"Analysis View Entry");
        SetSuggestedTable(Database::"Analysis View Budget Entry");
        SetSuggestedTable(Database::"Dimension Code Buffer");
        SetSuggestedTable(Database::"Dimension Selection Buffer");
        SetSuggestedTable(Database::"Selected Dimension");
        SetSuggestedTable(Database::"Excel Buffer");
        SetSuggestedTable(Database::"Budget Buffer");
        SetSuggestedTable(Database::"Payment Buffer");
        SetSuggestedTable(Database::"Dimension Entry Buffer");
        SetSuggestedTable(Database::"G/L Acc. Budget Buffer");
        SetSuggestedTable(Database::"Dimension Code Amount Buffer");
        SetSuggestedTable(Database::"G/L Account (Analysis View)");
        SetSuggestedTable(Database::"Report List Translation");
        SetSuggestedTable(Database::"Detailed Cust. Ledg. Entry");
        SetSuggestedTable(Database::"Detailed Vendor Ledg. Entry");
        SetSuggestedTable(Database::"VAT Registration No. Format");
        SetSuggestedTable(Database::"CV Ledger Entry Buffer");
        SetSuggestedTable(Database::"Detailed CV Ledg. Entry Buffer");
        SetSuggestedTable(Database::"Reconcile CV Acc Buffer");
        SetSuggestedTable(Database::"Entry No. Amount Buffer");
        SetSuggestedTable(Database::"Dimension Translation");
        SetSuggestedTable(Database::"Availability at Date");
        SetSuggestedTable(Database::"Handled IC Outbox Trans.");
        SetSuggestedTable(Database::"Handled IC Outbox Jnl. Line");
        SetSuggestedTable(Database::"IC Inbox Transaction");
        SetSuggestedTable(Database::"IC Inbox Jnl. Line");
        SetSuggestedTable(Database::"Handled IC Inbox Trans.");
        SetSuggestedTable(Database::"Handled IC Inbox Jnl. Line");
        SetSuggestedTable(Database::"IC Inbox/Outbox Jnl. Line Dim.");
        SetSuggestedTable(Database::"IC Comment Line");
        SetSuggestedTable(Database::"IC Outbox Sales Header");
        SetSuggestedTable(Database::"IC Outbox Sales Line");
        SetSuggestedTable(Database::"IC Outbox Purchase Header");
        SetSuggestedTable(Database::"IC Outbox Purchase Line");
        SetSuggestedTable(Database::"Handled IC Outbox Sales Header");
        SetSuggestedTable(Database::"Handled IC Outbox Sales Line");
        SetSuggestedTable(Database::"Handled IC Outbox Purch. Hdr");
        SetSuggestedTable(Database::"Handled IC Outbox Purch. Line");
        SetSuggestedTable(Database::"IC Inbox Sales Header");
        SetSuggestedTable(Database::"IC Inbox Sales Line");
        SetSuggestedTable(Database::"IC Inbox Purchase Header");
        SetSuggestedTable(Database::"IC Inbox Purchase Line");
        SetSuggestedTable(Database::"Handled IC Inbox Sales Header");
        SetSuggestedTable(Database::"Handled IC Inbox Sales Line");
        SetSuggestedTable(Database::"Handled IC Inbox Purch. Header");
        SetSuggestedTable(Database::"Handled IC Inbox Purch. Line");
        SetSuggestedTable(Database::"IC Document Dimension");
        SetSuggestedTable(Database::"Approval Entry");
        SetSuggestedTable(Database::"Approval Comment Line");
        SetSuggestedTable(Database::"Posted Approval Entry");
        SetSuggestedTable(Database::"Posted Approval Comment Line");
        SetSuggestedTable(Database::"Overdue Approval Entry");
        SetSuggestedTable(Database::"Sales Prepayment %");
        SetSuggestedTable(Database::"Purchase Prepayment %");
        SetSuggestedTable(Database::"Prepayment Inv. Line Buffer");
        SetSuggestedTable(Database::"Payment Term Translation");
        SetSuggestedTable(Database::"Shipment Method Translation");
        SetSuggestedTable(Database::"Payment Method Translation");
        SetSuggestedTable(Database::"Job Queue Category");
        SetSuggestedTable(Database::"Job Queue Entry");
        SetSuggestedTable(Database::"Job Queue Log Entry");
        SetSuggestedTable(Database::"Report Inbox");
        SetSuggestedTable(Database::"Dimension Set Entry");
        SetSuggestedTable(Database::"Dimension Set Tree Node");
        SetSuggestedTable(Database::"Reclas. Dimension Set Buffer");
        SetSuggestedTable(Database::"Change Global Dim. Log Entry");
        SetSuggestedTable(Database::"VAT Rate Change Setup");
        SetSuggestedTable(Database::"VAT Rate Change Conversion");
        SetSuggestedTable(Database::"VAT Rate Change Log Entry");
        SetSuggestedTable(Database::"VAT Clause");
        SetSuggestedTable(Database::"VAT Clause Translation");
        SetSuggestedTable(Database::"G/L Account Category");
        SetSuggestedTable(Database::"Error Message");
        SetSuggestedTable(Database::"Activity Log");
        SetSuggestedTable(Database::"Standard Address");
        SetSuggestedTable(Database::"VAT Report Header");
        SetSuggestedTable(Database::"VAT Report Line");
        SetSuggestedTable(Database::"VAT Statement Report Line");
        SetSuggestedTable(Database::"VAT Report Setup");
        SetSuggestedTable(Database::"VAT Report Line Relation");
        SetSuggestedTable(Database::"VAT Report Error Log");
        SetSuggestedTable(Database::"VAT Reports Configuration");
        SetSuggestedTable(Database::"VAT Report Archive");
        SetSuggestedTable(Database::"Date Lookup Buffer");
        SetSuggestedTable(Database::"Standard General Journal");
        SetSuggestedTable(Database::"Standard General Journal Line");
        SetSuggestedTable(Database::"Standard Item Journal");
        SetSuggestedTable(Database::"Standard Item Journal Line");
        SetSuggestedTable(Database::"Trailing Sales Orders Setup");
        SetSuggestedTable(Database::"Analysis Report Chart Line");
        SetSuggestedTable(Database::"Online Bank Acc. Link");
        SetSuggestedTable(Database::"Certificate of Supply");
        SetSuggestedTable(Database::Geolocation);
        SetSuggestedTable(Database::"Name/Value Buffer");
        SetSuggestedTable(Database::"Workflows Entries Buffer");
        SetSuggestedTable(Database::"Cash Flow Forecast");
        SetSuggestedTable(Database::"Cash Flow Account");
        SetSuggestedTable(Database::"Cash Flow Account Comment");
        SetSuggestedTable(Database::"Cash Flow Worksheet Line");
        SetSuggestedTable(Database::"Cash Flow Forecast Entry");
        SetSuggestedTable(Database::"Cash Flow Manual Revenue");
        SetSuggestedTable(Database::"Cash Flow Manual Expense");
        SetSuggestedTable(Database::"Cash Flow Report Selection");
        SetSuggestedTable(Database::"Excel Template Storage");
        SetSuggestedTable(Database::"Assembly Header");
        SetSuggestedTable(Database::"Assembly Line");
        SetSuggestedTable(Database::"Assemble-to-Order Link");
        SetSuggestedTable(Database::"Assembly Comment Line");
        SetSuggestedTable(Database::"Posted Assembly Header");
        SetSuggestedTable(Database::"Posted Assembly Line");
        SetSuggestedTable(Database::"Posted Assemble-to-Order Link");
        SetSuggestedTable(Database::"ATO Sales Buffer");
        SetSuggestedTable(Database::"Time Sheet Header");
        SetSuggestedTable(Database::"Time Sheet Line");
        SetSuggestedTable(Database::"Time Sheet Detail");
        SetSuggestedTable(Database::"Time Sheet Comment Line");
        SetSuggestedTable(Database::"Time Sheet Header Archive");
        SetSuggestedTable(Database::"Time Sheet Line Archive");
        SetSuggestedTable(Database::"Time Sheet Detail Archive");
        SetSuggestedTable(Database::"Time Sheet Cmt. Line Archive");
        SetSuggestedTable(Database::"Time Sheet Posting Entry");
        SetSuggestedTable(Database::"Time Sheet Chart Setup");
        SetSuggestedTable(Database::"Payment Registration Setup");
        SetSuggestedTable(Database::"Payment Registration Buffer");
        SetSuggestedTable(Database::"Document Search Result");
        SetSuggestedTable(Database::"Job Task");
        SetSuggestedTable(Database::"Job Task Dimension");
        SetSuggestedTable(Database::"Job Planning Line");
        SetSuggestedTable(Database::"Job WIP Entry");
        SetSuggestedTable(Database::"Job WIP G/L Entry");
        SetSuggestedTable(Database::"Job WIP Method");
        SetSuggestedTable(Database::"Job WIP Warning");
        SetSuggestedTable(Database::"Job Entry No.");
        SetSuggestedTable(Database::"Job Buffer");
        SetSuggestedTable(Database::"Job WIP Buffer");
        SetSuggestedTable(Database::"Job Difference Buffer");
        SetSuggestedTable(Database::"Job Usage Link");
        SetSuggestedTable(Database::"Job WIP Total");
        SetSuggestedTable(Database::"Job Planning Line Invoice");
        SetSuggestedTable(Database::"Job Planning Line - Calendar");
        SetSuggestedTable(Database::"Sorting Table");
        SetSuggestedTable(Database::"Reminder Terms Translation");
        SetSuggestedTable(Database::"Line Fee Note on Report Hist.");
        SetSuggestedTable(Database::"Payment Reporting Argument");
        SetSuggestedTable(Database::"Cost Journal Template");
        SetSuggestedTable(Database::"Cost Journal Line");
        SetSuggestedTable(Database::"Cost Journal Batch");
        SetSuggestedTable(Database::"Cost Type");
        SetSuggestedTable(Database::"Cost Entry");
        SetSuggestedTable(Database::"Cost Register");
        SetSuggestedTable(Database::"Cost Allocation Source");
        SetSuggestedTable(Database::"Cost Allocation Target");
        SetSuggestedTable(Database::"Cost Budget Entry");
        SetSuggestedTable(Database::"Cost Budget Name");
        SetSuggestedTable(Database::"Cost Budget Register");
        SetSuggestedTable(Database::"Cost Center");
        SetSuggestedTable(Database::"Cost Object");
        SetSuggestedTable(Database::"Cost Budget Buffer");
        SetSuggestedTable(Database::"Report Totals Buffer");
        SetSuggestedTable(Database::"Credit Transfer Register");
        SetSuggestedTable(Database::"Credit Transfer Entry");
        SetSuggestedTable(Database::"Direct Debit Collection");
        SetSuggestedTable(Database::"Direct Debit Collection Entry");
        SetSuggestedTable(Database::"Credit Trans Re-export History");
        SetSuggestedTable(Database::"Data Exchange Type");
        SetSuggestedTable(Database::"Intermediate Data Import");
        SetSuggestedTable(Database::"Data Exch.");
        SetSuggestedTable(Database::"Data Exch. Field");
        SetSuggestedTable(Database::"Data Exch. Def");
        SetSuggestedTable(Database::"Data Exch. Column Def");
        SetSuggestedTable(Database::"Data Exch. Mapping");
        SetSuggestedTable(Database::"Data Exch. Field Mapping");
        SetSuggestedTable(Database::"Payment Export Data");
        SetSuggestedTable(Database::"Data Exch. Line Def");
        SetSuggestedTable(Database::"Payment Jnl. Export Error Text");
        SetSuggestedTable(Database::"Payment Export Remittance Text");
        SetSuggestedTable(Database::"SEPA Direct Debit Mandate");
        SetSuggestedTable(Database::"Positive Pay Entry");
        SetSuggestedTable(Database::"Positive Pay Entry Detail");
        SetSuggestedTable(Database::"Transformation Rule");
        SetSuggestedTable(Database::"Positive Pay Header");
        SetSuggestedTable(Database::"Positive Pay Detail");
        SetSuggestedTable(Database::"Positive Pay Footer");
        SetSuggestedTable(Database::"Ledger Entry Matching Buffer");
        SetSuggestedTable(Database::"Bank Stmt Multiple Match Line");
        SetSuggestedTable(Database::"Bank Statement Matching Buffer");
        SetSuggestedTable(Database::"Text-to-Account Mapping");
        SetSuggestedTable(Database::"Bank Pmt. Appl. Rule");
        SetSuggestedTable(Database::"Data Exch. Field Mapping Buf.");
        SetSuggestedTable(Database::"Bank Clearing Standard");
        SetSuggestedTable(Database::"Outstanding Bank Transaction");
        SetSuggestedTable(Database::"Payment Application Proposal");
        SetSuggestedTable(Database::"Applied Payment Entry");
        SetSuggestedTable(Database::"Posted Payment Recon. Hdr");
        SetSuggestedTable(Database::"Posted Payment Recon. Line");
        SetSuggestedTable(Database::"Payment Matching Details");
        SetSuggestedTable(Database::"Chart Definition");
        SetSuggestedTable(Database::"Last Used Chart");
        SetSuggestedTable(Database::"Activities Cue");
        SetSuggestedTable(Database::"Sales by Cust. Grp.Chart Setup");
        SetSuggestedTable(Database::"Top Customers By Sales Buffer");
        SetSuggestedTable(Database::"Customer Templ.");
        SetSuggestedTable(Database::"Item Templ.");
        SetSuggestedTable(Database::"Vendor Templ.");
        SetSuggestedTable(Database::"Employee Templ.");
        SetSuggestedTable(Database::"Service Connection");
        SetSuggestedTable(Database::"Role Center Notifications");
        SetSuggestedTable(Database::"Named Forward Link");
        SetSuggestedTable(Database::"RC Headlines User Data");
        SetSuggestedTable(Database::"Sent Notification Entry");
        SetSuggestedTable(Database::"Invoiced Booking Item");
        SetSuggestedTable(Database::"Payroll Setup");
        SetSuggestedTable(Database::"Import G/L Transaction");
        SetSuggestedTable(Database::"Payroll Import Buffer");
        SetSuggestedTable(Database::"Option Lookup Buffer");
        SetSuggestedTable(Database::"Deferral Template");
        SetSuggestedTable(Database::"Deferral Header");
        SetSuggestedTable(Database::"Deferral Line");
        SetSuggestedTable(Database::"Posted Deferral Header");
        SetSuggestedTable(Database::"Posted Deferral Line");
        SetSuggestedTable(Database::"VAT Setup Posting Groups");
        SetSuggestedTable(Database::"VAT Assisted Setup Templates");
        SetSuggestedTable(Database::"VAT Assisted Setup Bus. Grp.");
        SetSuggestedTable(Database::"Cancelled Document");
        SetSuggestedTable(Database::"Time Series Buffer");
        SetSuggestedTable(Database::"Time Series Forecast");
        SetSuggestedTable(Database::"Sales Document Icon");
        SetSuggestedTable(Database::"Calendar Event");
        SetSuggestedTable(Database::"Calendar Event User Config.");
        SetSuggestedTable(Database::Contact);
        SetSuggestedTable(Database::"Contact Alt. Address");
        SetSuggestedTable(Database::"Contact Alt. Addr. Date Range");
        SetSuggestedTable(Database::"Business Relation");
        SetSuggestedTable(Database::"Contact Business Relation");
        SetSuggestedTable(Database::"Mailing Group");
        SetSuggestedTable(Database::"Contact Mailing Group");
        SetSuggestedTable(Database::"Industry Group");
        SetSuggestedTable(Database::"Contact Industry Group");
        SetSuggestedTable(Database::"Web Source");
        SetSuggestedTable(Database::"Contact Web Source");
        SetSuggestedTable(Database::"Rlshp. Mgt. Comment Line");
        SetSuggestedTable(Database::Attachment);
        SetSuggestedTable(Database::"Interaction Group");
        SetSuggestedTable(Database::"Interaction Template");
        SetSuggestedTable(Database::"Interaction Log Entry");
        SetSuggestedTable(Database::"Job Responsibility");
        SetSuggestedTable(Database::"Contact Job Responsibility");
        SetSuggestedTable(Database::Salutation);
        SetSuggestedTable(Database::"Salutation Formula");
        SetSuggestedTable(Database::"Organizational Level");
        SetSuggestedTable(Database::Campaign);
        SetSuggestedTable(Database::"Campaign Entry");
        SetSuggestedTable(Database::"Campaign Status");
        SetSuggestedTable(Database::"Delivery Sorter");
        SetSuggestedTable(Database::"Segment Header");
        SetSuggestedTable(Database::"Segment Line");
        SetSuggestedTable(Database::"Segment History");
        SetSuggestedTable(Database::"To-do");
        SetSuggestedTable(Database::Team);
        SetSuggestedTable(Database::"Team Salesperson");
        SetSuggestedTable(Database::"Contact Duplicate");
        SetSuggestedTable(Database::"Cont. Duplicate Search String");
        SetSuggestedTable(Database::"Contact Profile Answer");
        SetSuggestedTable(Database::"Sales Cycle");
        SetSuggestedTable(Database::"Sales Cycle Stage");
        SetSuggestedTable(Database::Opportunity);
        SetSuggestedTable(Database::"Opportunity Entry");
        SetSuggestedTable(Database::"Close Opportunity Code");
        SetSuggestedTable(Database::"Duplicate Search String Setup");
        SetSuggestedTable(Database::"Segment Wizard Filter");
        SetSuggestedTable(Database::"Segment Criteria Line");
        SetSuggestedTable(Database::"Saved Segment Criteria");
        SetSuggestedTable(Database::"Saved Segment Criteria Line");
        SetSuggestedTable(Database::"Contact Value");
        SetSuggestedTable(Database::"RM Matrix Management");
        SetSuggestedTable(Database::"Sales Header Archive");
        SetSuggestedTable(Database::"Sales Line Archive");
        SetSuggestedTable(Database::"Purchase Header Archive");
        SetSuggestedTable(Database::"Purchase Line Archive");
        SetSuggestedTable(Database::Rating);
        SetSuggestedTable(Database::"Contact Dupl. Details Buffer");
        SetSuggestedTable(Database::"Inter. Log Entry Comment Line");
        SetSuggestedTable(Database::"Current Salesperson");
        SetSuggestedTable(Database::"Purch. Comment Line Archive");
        SetSuggestedTable(Database::"Sales Comment Line Archive");
        SetSuggestedTable(Database::"Deferral Header Archive");
        SetSuggestedTable(Database::"Deferral Line Archive");
        SetSuggestedTable(Database::Attendee);
        SetSuggestedTable(Database::Employee);
        SetSuggestedTable(Database::"Alternative Address");
        SetSuggestedTable(Database::Qualification);
        SetSuggestedTable(Database::"Employee Qualification");
        SetSuggestedTable(Database::Relative);
        SetSuggestedTable(Database::"Employee Relative");
        SetSuggestedTable(Database::"Cause of Absence");
        SetSuggestedTable(Database::"Employee Absence");
        SetSuggestedTable(Database::"Human Resource Comment Line");
        SetSuggestedTable(Database::Union);
        SetSuggestedTable(Database::"Cause of Inactivity");
        SetSuggestedTable(Database::"Employment Contract");
        SetSuggestedTable(Database::"Employee Statistics Group");
        SetSuggestedTable(Database::"Misc. Article");
        SetSuggestedTable(Database::"Misc. Article Information");
        SetSuggestedTable(Database::Confidential);
        SetSuggestedTable(Database::"Confidential Information");
        SetSuggestedTable(Database::"HR Confidential Comment Line");
        SetSuggestedTable(Database::"Employee Posting Group");
        SetSuggestedTable(Database::"Employee Ledger Entry");
        SetSuggestedTable(Database::"Detailed Employee Ledger Entry");
        SetSuggestedTable(Database::"Payable Employee Ledger Entry");
        SetSuggestedTable(Database::"Employee Payment Buffer");
        SetSuggestedTable(Database::"Exchange Folder");
        SetSuggestedTable(Database::"Item Variant");
        SetSuggestedTable(Database::"Production Order");
        SetSuggestedTable(Database::"Prod. Order Line");
        SetSuggestedTable(Database::"Prod. Order Component");
        SetSuggestedTable(Database::"Prod. Order Routing Line");
        SetSuggestedTable(Database::"Prod. Order Capacity Need");
        SetSuggestedTable(Database::"Prod. Order Routing Tool");
        SetSuggestedTable(Database::"Prod. Order Routing Personnel");
        SetSuggestedTable(Database::"Prod. Order Rtng Qlty Meas.");
        SetSuggestedTable(Database::"Prod. Order Comment Line");
        SetSuggestedTable(Database::"Prod. Order Rtng Comment Line");
        SetSuggestedTable(Database::"Prod. Order Comp. Cmt Line");
        SetSuggestedTable(Database::"Planning Error Log");
        SetSuggestedTable(Database::"Sales Invoice Entity Aggregate");
        SetSuggestedTable(Database::"Purch. Inv. Entity Aggregate");
        SetSuggestedTable(Database::"Tax Group Buffer");
        SetSuggestedTable(Database::"Trial Balance Entity Buffer");
        SetSuggestedTable(Database::"Sales Order Entity Buffer");
        SetSuggestedTable(Database::"Purchase Order Entity Buffer");
        SetSuggestedTable(Database::"Aged Report Entity");
        SetSuggestedTable(Database::"Tax Rate Buffer");
        SetSuggestedTable(Database::"Tax Area Buffer");
        SetSuggestedTable(Database::"Sales Quote Entity Buffer");
        SetSuggestedTable(Database::"Sales Cr. Memo Entity Buffer");
        SetSuggestedTable(Database::"Unplanned Demand");
        SetSuggestedTable(Database::"Manufacturing User Template");
        SetSuggestedTable(Database::"Inventory Event Buffer");
        SetSuggestedTable(Database::"Inventory Page Data");
        SetSuggestedTable(Database::"Timeline Event");
        SetSuggestedTable(Database::"Timeline Event Change");
        SetSuggestedTable(Database::"Fixed Asset");
        SetSuggestedTable(Database::"FA Ledger Entry");
        SetSuggestedTable(Database::"FA Posting Type Setup");
        SetSuggestedTable(Database::"FA Journal Setup");
        SetSuggestedTable(Database::"FA Posting Group");
        SetSuggestedTable(Database::"FA Class");
        SetSuggestedTable(Database::"FA Subclass");
        SetSuggestedTable(Database::"FA Location");
        SetSuggestedTable(Database::"Depreciation Book");
        SetSuggestedTable(Database::"FA Depreciation Book");
        SetSuggestedTable(Database::"FA Allocation");
        SetSuggestedTable(Database::"Maintenance Registration");
        SetSuggestedTable(Database::"FA Register");
        SetSuggestedTable(Database::"FA Journal Template");
        SetSuggestedTable(Database::"FA Journal Batch");
        SetSuggestedTable(Database::"FA Journal Line");
        SetSuggestedTable(Database::"FA Reclass. Journal Template");
        SetSuggestedTable(Database::"FA Reclass. Journal Batch");
        SetSuggestedTable(Database::"FA Reclass. Journal Line");
        SetSuggestedTable(Database::"Maintenance Ledger Entry");
        SetSuggestedTable(Database::Maintenance);
        SetSuggestedTable(Database::Insurance);
        SetSuggestedTable(Database::"Ins. Coverage Ledger Entry");
        SetSuggestedTable(Database::"Insurance Type");
        SetSuggestedTable(Database::"Insurance Journal Template");
        SetSuggestedTable(Database::"Insurance Journal Batch");
        SetSuggestedTable(Database::"Insurance Journal Line");
        SetSuggestedTable(Database::"Insurance Register");
        SetSuggestedTable(Database::"FA G/L Posting Buffer");
        SetSuggestedTable(Database::"Main Asset Component");
        SetSuggestedTable(Database::"FA Buffer Projection");
        SetSuggestedTable(Database::"Depreciation Table Header");
        SetSuggestedTable(Database::"Depreciation Table Line");
        SetSuggestedTable(Database::"FA Posting Type");
        SetSuggestedTable(Database::"FA Date Type");
        SetSuggestedTable(Database::"Depreciation Table Buffer");
        SetSuggestedTable(Database::"FA Matrix Posting Type");
        SetSuggestedTable(Database::"FA Posting Group Buffer");
        SetSuggestedTable(Database::"Total Value Insured");
        SetSuggestedTable(Database::"Stockkeeping Unit");
        SetSuggestedTable(Database::"Stockkeeping Unit Comment Line");
        SetSuggestedTable(Database::"Responsibility Center");
        SetSuggestedTable(Database::"Item Substitution");
        SetSuggestedTable(Database::"Substitution Condition");
        SetSuggestedTable(Database::"Nonstock Item");
        SetSuggestedTable(Database::Manufacturer);
        SetSuggestedTable(Database::Purchasing);
        SetSuggestedTable(Database::"Item Category");
        SetSuggestedTable(Database::"Transfer Header");
        SetSuggestedTable(Database::"Transfer Line");
        SetSuggestedTable(Database::"Transfer Route");
        SetSuggestedTable(Database::"Transfer Shipment Header");
        SetSuggestedTable(Database::"Transfer Shipment Line");
        SetSuggestedTable(Database::"Transfer Receipt Header");
        SetSuggestedTable(Database::"Transfer Receipt Line");
        SetSuggestedTable(Database::"Inventory Comment Line");
        SetSuggestedTable(Database::"Warehouse Request");
        SetSuggestedTable(Database::"Warehouse Activity Header");
        SetSuggestedTable(Database::"Warehouse Activity Line");
        SetSuggestedTable(Database::"Whse. Cross-Dock Opportunity");
        SetSuggestedTable(Database::"Warehouse Comment Line");
        SetSuggestedTable(Database::"Warehouse Source Filter");
        SetSuggestedTable(Database::"Registered Whse. Activity Hdr.");
        SetSuggestedTable(Database::"Registered Whse. Activity Line");
        SetSuggestedTable(Database::"Shipping Agent Services");
        SetSuggestedTable(Database::"Item Charge");
        SetSuggestedTable(Database::"Value Entry");
        SetSuggestedTable(Database::"Item Journal Buffer");
        SetSuggestedTable(Database::"Avg. Cost Adjmt. Entry Point");
        SetSuggestedTable(Database::"Item Charge Assignment (Purch)");
        SetSuggestedTable(Database::"Item Charge Assignment (Sales)");
        SetSuggestedTable(Database::"Rounding Residual Buffer");
        SetSuggestedTable(Database::"Post Value Entry to G/L");
        SetSuggestedTable(Database::"Inventory Posting Setup");
        SetSuggestedTable(Database::"Inventory Period");
        SetSuggestedTable(Database::"Inventory Period Entry");
        SetSuggestedTable(Database::"Cost Element Buffer");
        SetSuggestedTable(Database::"Item Statistics Buffer");
        SetSuggestedTable(Database::"Invt. Post to G/L Test Buffer");
        SetSuggestedTable(Database::"G/L - Item Ledger Relation");
        SetSuggestedTable(Database::"Availability Calc. Overview");
        SetSuggestedTable(Database::"Capacity Ledger Entry");
        SetSuggestedTable(Database::"Standard Cost Worksheet Name");
        SetSuggestedTable(Database::"Standard Cost Worksheet");
        SetSuggestedTable(Database::"Inventory Report Header");
        SetSuggestedTable(Database::"Inventory Report Entry");
        SetSuggestedTable(Database::"Average Cost Calc. Overview");
        SetSuggestedTable(Database::"Cost Share Buffer");
        SetSuggestedTable(Database::"Invt. Document Header");
        SetSuggestedTable(Database::"Invt. Document Line");
        SetSuggestedTable(Database::"Invt. Receipt Header");
        SetSuggestedTable(Database::"Invt. Receipt Line");
        SetSuggestedTable(Database::"Invt. Shipment Header");
        SetSuggestedTable(Database::"Invt. Shipment Line");
        SetSuggestedTable(Database::"Direct Trans. Header");
        SetSuggestedTable(Database::"Direct Trans. Line");
        SetSuggestedTable(Database::"BOM Buffer");
        SetSuggestedTable(Database::"Memoized Result");
        SetSuggestedTable(Database::"Item Availability by Date");
        SetSuggestedTable(Database::"BOM Warning Log");
        SetSuggestedTable(Database::"Transfer Route");
        SetSuggestedTable(Database::"Phys. Invt. Order Header");
        SetSuggestedTable(Database::"Phys. Invt. Order Line");
        SetSuggestedTable(Database::"Phys. Invt. Record Header");
        SetSuggestedTable(Database::"Phys. Invt. Record Line");
        SetSuggestedTable(Database::"Pstd. Phys. Invt. Order Hdr");
        SetSuggestedTable(Database::"Pstd. Phys. Invt. Order Line");
        SetSuggestedTable(Database::"Pstd. Phys. Invt. Record Hdr");
        SetSuggestedTable(Database::"Pstd. Phys. Invt. Record Line");
        SetSuggestedTable(Database::"Phys. Invt. Comment Line");
        SetSuggestedTable(Database::"Pstd. Phys. Invt. Tracking");
        SetSuggestedTable(Database::"Phys. Invt. Tracking");
        SetSuggestedTable(Database::"Exp. Phys. Invt. Tracking");
        SetSuggestedTable(Database::"Pstd. Exp. Phys. Invt. Track");
        SetSuggestedTable(Database::"Phys. Invt. Count Buffer");
        SetSuggestedTable(Database::"Error Buffer");
        SetSuggestedTable(Database::"Inventory Adjustment Buffer");
        SetSuggestedTable(Database::"Inventory Adjmt. Entry (Order)");
        SetSuggestedTable(Database::"Service Header");
        SetSuggestedTable(Database::"Service Item Line");
        SetSuggestedTable(Database::"Service Line");
        SetSuggestedTable(Database::"Service Order Type");
        SetSuggestedTable(Database::"Service Item Group");
        SetSuggestedTable(Database::"Service Cost");
        SetSuggestedTable(Database::"Service Comment Line");
        SetSuggestedTable(Database::"Service Ledger Entry");
        SetSuggestedTable(Database::"Warranty Ledger Entry");
        SetSuggestedTable(Database::"Service Shipment Buffer");
        SetSuggestedTable(Database::"Service Hour");
        SetSuggestedTable(Database::"Service Mgt. Setup");
        SetSuggestedTable(Database::"Service Document Log");
        SetSuggestedTable(Database::Loaner);
        SetSuggestedTable(Database::"Loaner Entry");
        SetSuggestedTable(Database::"Fault Area");
        SetSuggestedTable(Database::"Symptom Code");
        SetSuggestedTable(Database::"Fault Reason Code");
        SetSuggestedTable(Database::"Fault Code");
        SetSuggestedTable(Database::"Resolution Code");
        SetSuggestedTable(Database::"Fault/Resol. Cod. Relationship");
        SetSuggestedTable(Database::"Fault Area/Symptom Code");
        SetSuggestedTable(Database::"Repair Status");
        SetSuggestedTable(Database::"Service Status Priority Setup");
        SetSuggestedTable(Database::"Service Shelf");
        SetSuggestedTable(Database::"Service Order Posting Buffer");
        SetSuggestedTable(Database::"Service Register");
        SetSuggestedTable(Database::"Service Email Queue");
        SetSuggestedTable(Database::"Service Document Register");
        SetSuggestedTable(Database::"Service Item");
        SetSuggestedTable(Database::"Service Item Component");
        SetSuggestedTable(Database::"Service Item Log");
        SetSuggestedTable(Database::"Troubleshooting Header");
        SetSuggestedTable(Database::"Troubleshooting Line");
        SetSuggestedTable(Database::"Service Order Allocation");
        SetSuggestedTable(Database::"Resource Location");
        SetSuggestedTable(Database::"Work-Hour Template");
        SetSuggestedTable(Database::"Skill Code");
        SetSuggestedTable(Database::"Resource Skill");
        SetSuggestedTable(Database::"Service Zone");
        SetSuggestedTable(Database::"Resource Service Zone");
        SetSuggestedTable(Database::"Service Contract Line");
        SetSuggestedTable(Database::"Service Contract Header");
        SetSuggestedTable(Database::"Contract Group");
        SetSuggestedTable(Database::"Contract Change Log");
        SetSuggestedTable(Database::"Service Contract Template");
        SetSuggestedTable(Database::"Contract Gain/Loss Entry");
        SetSuggestedTable(Database::"Filed Service Contract Header");
        SetSuggestedTable(Database::"Filed Contract Line");
        SetSuggestedTable(Database::"Contract/Service Discount");
        SetSuggestedTable(Database::"Service Contract Account Group");
        SetSuggestedTable(Database::"Service Shipment Item Line");
        SetSuggestedTable(Database::"Service Shipment Header");
        SetSuggestedTable(Database::"Service Shipment Line");
        SetSuggestedTable(Database::"Service Invoice Header");
        SetSuggestedTable(Database::"Service Invoice Line");
        SetSuggestedTable(Database::"Service Cr.Memo Header");
        SetSuggestedTable(Database::"Service Cr.Memo Line");
        SetSuggestedTable(Database::"Standard Service Code");
        SetSuggestedTable(Database::"Standard Service Line");
        SetSuggestedTable(Database::"Standard Service Item Gr. Code");
        SetSuggestedTable(Database::"Service Price Group");
        SetSuggestedTable(Database::"Serv. Price Group Setup");
        SetSuggestedTable(Database::"Service Price Adjustment Group");
        SetSuggestedTable(Database::"Serv. Price Adjustment Detail");
        SetSuggestedTable(Database::"Service Line Price Adjmt.");
        SetSuggestedTable(Database::"Transfer Route");
        SetSuggestedTable(Database::"Phys. Invt. Order Line");
        SetSuggestedTable(Database::"Contract Group");
        SetSuggestedTable(Database::"Item Tracking Code");
        SetSuggestedTable(Database::"Serial No. Information");
        SetSuggestedTable(Database::"Lot No. Information");
        SetSuggestedTable(Database::"Item Tracking Comment");
        SetSuggestedTable(Database::"Item Tracing Buffer");
        SetSuggestedTable(Database::"Item Entry Relation");
        SetSuggestedTable(Database::"Value Entry Relation");
        SetSuggestedTable(Database::"Whse. Item Entry Relation");
        SetSuggestedTable(Database::"Item Tracing Buffer");
        SetSuggestedTable(Database::"Item Tracing History Buffer");
        SetSuggestedTable(Database::"Whse. Item Tracking Line");
        SetSuggestedTable(Database::"Return Reason");
        SetSuggestedTable(Database::"Return Shipment Header");
        SetSuggestedTable(Database::"Return Shipment Line");
        SetSuggestedTable(Database::"Return Receipt Header");
        SetSuggestedTable(Database::"Return Receipt Line");
        SetSuggestedTable(Database::"Returns-Related Document");
        SetSuggestedTable(Database::"Phys. Invt. Order Line");
        SetSuggestedTable(Database::"Price List Header");
        SetSuggestedTable(Database::"Price List Line");
        SetSuggestedTable(Database::"Price Asset");
        SetSuggestedTable(Database::"Price Source");
        SetSuggestedTable(Database::"Price Calculation Setup");
        SetSuggestedTable(Database::"Price Calculation Buffer");
        SetSuggestedTable(Database::"Dtld. Price Calculation Setup");
        SetSuggestedTable(Database::"Duplicate Price Line");
        SetSuggestedTable(Database::"Sales Price Access");
        SetSuggestedTable(Database::"Sales Discount Access");
        SetSuggestedTable(Database::"Purchase Price Access");
        SetSuggestedTable(Database::"Purchase Discount Access");
        SetSuggestedTable(Database::"Price Line Filters");
        SetSuggestedTable(Database::"Campaign Target Group");
        SetSuggestedTable(Database::"Analysis Field Value");
        SetSuggestedTable(Database::"Analysis Report Name");
        SetSuggestedTable(Database::"Analysis Line Template");
        SetSuggestedTable(Database::"Analysis Type");
        SetSuggestedTable(Database::"Analysis Line");
        SetSuggestedTable(Database::"Analysis Column Template");
        SetSuggestedTable(Database::"Analysis Column");
        SetSuggestedTable(Database::"Item Budget Name");
        SetSuggestedTable(Database::"Item Budget Entry");
        SetSuggestedTable(Database::"Item Budget Buffer");
        SetSuggestedTable(Database::"Item Analysis View");
        SetSuggestedTable(Database::"Item Analysis View Filter");
        SetSuggestedTable(Database::"Item Analysis View Entry");
        SetSuggestedTable(Database::"Item Analysis View Budg. Entry");
        SetSuggestedTable(Database::"Analysis Dim. Selection Buffer");
        SetSuggestedTable(Database::"Analysis Selected Dimension");
        SetSuggestedTable(Database::"Sales Shipment Buffer");
        SetSuggestedTable(Database::Zone);
        SetSuggestedTable(Database::"Warehouse Employee");
        SetSuggestedTable(Database::"Bin Content");
        SetSuggestedTable(Database::"Bin Type");
        SetSuggestedTable(Database::"Warehouse Class");
        SetSuggestedTable(Database::"Special Equipment");
        SetSuggestedTable(Database::"Put-away Template Header");
        SetSuggestedTable(Database::"Put-away Template Line");
        SetSuggestedTable(Database::"Warehouse Journal Template");
        SetSuggestedTable(Database::"Warehouse Journal Batch");
        SetSuggestedTable(Database::"Warehouse Journal Line");
        SetSuggestedTable(Database::"Warehouse Entry");
        SetSuggestedTable(Database::"Warehouse Register");
        SetSuggestedTable(Database::"Warehouse Receipt Header");
        SetSuggestedTable(Database::"Warehouse Receipt Line");
        SetSuggestedTable(Database::"Posted Whse. Receipt Header");
        SetSuggestedTable(Database::"Posted Whse. Receipt Line");
        SetSuggestedTable(Database::"Warehouse Shipment Header");
        SetSuggestedTable(Database::"Warehouse Shipment Line");
        SetSuggestedTable(Database::"Posted Whse. Shipment Header");
        SetSuggestedTable(Database::"Posted Whse. Shipment Line");
        SetSuggestedTable(Database::"Whse. Put-away Request");
        SetSuggestedTable(Database::"Whse. Pick Request");
        SetSuggestedTable(Database::"Whse. Worksheet Line");
        SetSuggestedTable(Database::"Whse. Worksheet Name");
        SetSuggestedTable(Database::"Whse. Worksheet Template");
        SetSuggestedTable(Database::"Bin Content Buffer");
        SetSuggestedTable(Database::"Whse. Internal Put-away Header");
        SetSuggestedTable(Database::"Whse. Internal Put-away Line");
        SetSuggestedTable(Database::"Whse. Internal Pick Header");
        SetSuggestedTable(Database::"Whse. Internal Pick Line");
        SetSuggestedTable(Database::"Bin Template");
        SetSuggestedTable(Database::"Bin Creation Wksh. Template");
        SetSuggestedTable(Database::"Bin Creation Wksh. Name");
        SetSuggestedTable(Database::"Bin Creation Worksheet Line");
        SetSuggestedTable(Database::"Posted Invt. Put-away Header");
        SetSuggestedTable(Database::"Posted Invt. Put-away Line");
        SetSuggestedTable(Database::"Posted Invt. Pick Header");
        SetSuggestedTable(Database::"Posted Invt. Pick Line");
        SetSuggestedTable(Database::"Registered Invt. Movement Hdr.");
        SetSuggestedTable(Database::"Registered Invt. Movement Line");
        SetSuggestedTable(Database::"Internal Movement Header");
        SetSuggestedTable(Database::"Internal Movement Line");
        SetSuggestedTable(Database::Bin);
        SetSuggestedTable(Database::"Reservation Entry Buffer");
        SetSuggestedTable(Database::"Phys. Invt. Item Selection");
        SetSuggestedTable(Database::"Phys. Invt. Counting Period");
        SetSuggestedTable(Database::"Item Attribute");
        SetSuggestedTable(Database::"Item Attribute Value");
        SetSuggestedTable(Database::"Item Attribute Translation");
        SetSuggestedTable(Database::"Item Attr. Value Translation");
        SetSuggestedTable(Database::"Item Attribute Value Selection");
        SetSuggestedTable(Database::"Item Attribute Value Mapping");
        SetSuggestedTable(Database::"Filter Item Attributes Buffer");
        SetSuggestedTable(Database::"Base Calendar");
        SetSuggestedTable(Database::"Base Calendar Change");
        SetSuggestedTable(Database::"Customized Calendar Change");
        SetSuggestedTable(Database::"Customized Calendar Entry");
        SetSuggestedTable(Database::"Where Used Base Calendar");
        SetSuggestedTable(Database::"Miniform Header");
        SetSuggestedTable(Database::"Miniform Line");
        SetSuggestedTable(Database::"Miniform Function Group");
        SetSuggestedTable(Database::"Miniform Function");
        SetSuggestedTable(Database::"Item Identifier");
        SetSuggestedTable(Database::"Dimensions Field Map");
        SetSuggestedTable(Database::"Record Set Definition");
        SetSuggestedTable(Database::"Record Set Tree");
        SetSuggestedTable(Database::"Record Set Buffer");
        SetSuggestedTable(Database::"Field Buffer");
        SetSuggestedTable(Database::"Over-Receipt Code");
        SetSuggestedTable(Database::"Email Outbox");
        SetSuggestedTable(Database::"Team Member Cue");
        SetSuggestedTable(Database::"Warehouse Basic Cue");
        SetSuggestedTable(Database::"Warehouse WMS Cue");
        SetSuggestedTable(Database::"Service Cue");
        SetSuggestedTable(Database::"Sales Cue");
        SetSuggestedTable(Database::"Finance Cue");
        SetSuggestedTable(Database::"Purchase Cue");
        SetSuggestedTable(Database::"Manufacturing Cue");
        SetSuggestedTable(Database::"Job Cue");
        SetSuggestedTable(Database::"Warehouse Worker WMS Cue");
        SetSuggestedTable(Database::"Administration Cue");
        SetSuggestedTable(Database::"SB Owner Cue");
        SetSuggestedTable(Database::"RapidStart Services Cue");
        SetSuggestedTable(Database::"Relationship Mgmt. Cue");
        SetSuggestedTable(Database::"O365 Sales Cue");
        SetSuggestedTable(Database::"Accounting Services Cue");
        SetSuggestedTable(Database::"Autocomplete Address");
        SetSuggestedTable(Database::"Postcode Service Config");
        SetSuggestedTable(Database::"My Customer");
        SetSuggestedTable(Database::"My Vendor");
        SetSuggestedTable(Database::"My Item");
        SetSuggestedTable(Database::"My Account");
        SetSuggestedTable(Database::"My Job");
        SetSuggestedTable(Database::"My Time Sheets");


        RecordDeletion.SetRange("Delete Records", true);
        AfterSuggestionDeleteCount := RecordDeletion.Count();
        Message(RecordsWereSuggestedMsg, AfterSuggestionDeleteCount - BeforeSuggestionDeleteCount);
    end;
}