{
   Double commander
   -------------------------------------------------------------------------
   Remote procedure call implementation (Windows)

   Copyright (C) 2019 Alexander Koblov (alexx2000@mail.ru)

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program. If not, see <http://www.gnu.org/licenses/>.
}

unit uClientServer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uService;

type

  { TPipeTransport }

  TPipeTransport = class(TBaseTransport)
  private
    FPipe: THandle;
    FProcessID: UInt32;
    FAddress: UnicodeString;
  private
    procedure Connect;
  public
    procedure Disconnect; override;
    procedure WriteHandle(AHandle: THandle); override;
    function ReadHandle(var AHandle: THandle) : Int64; override;
    procedure WriteBuffer(const AData; const ALength : Int64); override;
    function ReadBuffer(var AData; const ALength : Int64) : Int64; override;
  public
    constructor Create(APipe: THandle; ProcessID: UInt32);
    constructor Create(Address: String);
    destructor Destroy; override;
  end;

  { TClientHandlerThread }

  TClientHandlerThread = class(TClientThread)
  public
    constructor Create(APipe : THandle; AOwner : TBaseService);
  end;
  
  { TServerListnerThread }

  TServerListnerThread = class(TServerThread)
  private
    FEvent: THandle;
  public
    constructor Create(AOwner : TBaseService); override;
    destructor Destroy; override;
    procedure Execute; override;
  end;

implementation

uses 
  JwaWinNT, JwaAclApi, JwaAccCtrl, JwaWinBase, Windows, uNamedPipes, uDebug;

{ TPipeTransport }

procedure TPipeTransport.Connect;
begin
  if (FPipe = 0) then
  begin
    DCDebug('Connect to ', FAddress,'_');

    FPipe:= CreateFileW(PWideChar('\\.\pipe\' + FAddress),
      GENERIC_WRITE or
      GENERIC_READ,
      FILE_SHARE_READ or
      FILE_SHARE_WRITE,
      nil,
      OPEN_EXISTING,
      FILE_FLAG_OVERLAPPED,
      0);

    if FPipe = INVALID_HANDLE_VALUE then RaiseLastOSError;
  end;
end;

procedure TPipeTransport.Disconnect;
begin
  CloseHandle(FPipe);
  FPipe:= 0;
end;

procedure TPipeTransport.WriteHandle(AHandle: THandle);
var
  hProcess: THandle;
  hDuplicate: THandle;
begin
  hProcess:= OpenProcess(PROCESS_DUP_HANDLE, False, FProcessID);
  if (hProcess <> 0) then
  begin
    if DuplicateHandle(GetCurrentProcess(), AHandle, hProcess, @hDuplicate, 0, False, DUPLICATE_SAME_ACCESS or DUPLICATE_CLOSE_SOURCE) then
      WriteBuffer(hDuplicate, SizeOf(hDuplicate));
    CloseHandle(hProcess);
  end;
end;

function TPipeTransport.ReadHandle(var AHandle: THandle): Int64;
begin
  Result:= ReadBuffer(AHandle, SizeOf(AHandle));
end;

procedure TPipeTransport.WriteBuffer(const AData; const ALength : Int64);
var
  P: PByte;
  Len: Int64;
  LastError: DWORD;
  Overlapped: TOverlapped;
  dwNumberOfBytesTransferred: DWORD;
begin
  Connect;
  Len := ALength;
  P := PByte(@AData);
  Repeat
    LastError := 0;
    dwNumberOfBytesTransferred:= 0;
    ZeroMemory(@Overlapped, SizeOf(TOverlapped));

    if not WriteFile(FPipe, P^, Len, dwNumberOfBytesTransferred, @Overlapped) then
      LastError := GetLastError;

    if (LastError <> 0) and (LastError <> ERROR_IO_PENDING) then
      raise EInOutError.Create(SysErrorMessage(LastError));

    LastError := WaitForSingleObject(FPipe, INFINITE);

    if LastError = WAIT_TIMEOUT then
    begin
      raise EInOutError.Create(SysErrorMessage(LastError));
    end;

    if not GetOverlappedResult(FPipe, Overlapped, dwNumberOfBytesTransferred, False) then
      raise EInOutError.Create(SysErrorMessage(GetLastError));

    if (dwNumberOfBytesTransferred > 0) then
    begin
      Inc(P, dwNumberOfBytesTransferred);
      Dec(Len, dwNumberOfBytesTransferred);
    end;
  until (Len = 0);
end;

function TPipeTransport.ReadBuffer(var AData; const ALength : Int64) : Int64;
Var
  P : PByte;
  Len : Int64;
  LastError: DWORD;
  Overlapped: TOverlapped;
  dwNumberOfBytesTransferred: DWORD;
begin
  Len := ALength;
  P := PByte(@AData);
  repeat
    LastError := 0;
    dwNumberOfBytesTransferred:= 0;
    ZeroMemory(@Overlapped, SizeOf(TOverlapped));

    if not ReadFile(FPipe, P^, Len, dwNumberOfBytesTransferred, @Overlapped) then
      LastError := GetLastError;

    if (LastError <> 0) and (LastError <> ERROR_IO_PENDING) then
      raise EInOutError.Create(SysErrorMessage(LastError));

    LastError := WaitForSingleObject(FPipe, INFINITE);

    if LastError = WAIT_TIMEOUT then
      raise EInOutError.Create(SysErrorMessage(LastError));

    if not GetOverlappedResult(FPipe, Overlapped, dwNumberOfBytesTransferred, False) then
      raise EInOutError.Create(SysErrorMessage(GetLastError));

    if (dwNumberOfBytesTransferred = 0) then
      raise EInOutError.Create(EmptyStr);

    if (dwNumberOfBytesTransferred > 0) then
    begin
      Inc(P, dwNumberOfBytesTransferred);
      Dec(Len, dwNumberOfBytesTransferred);
    end
  until (Len = 0);
  Result := ALength;
end;

constructor TPipeTransport.Create(APipe: THandle; ProcessID: UInt32);
begin
  FPipe:= APipe;
  FProcessID:= ProcessID;
end;

constructor TPipeTransport.Create(Address: String);
begin
  FAddress:= UTF8Decode(Address);
end;

destructor TPipeTransport.Destroy;
begin
  CloseHandle(FPipe);
  inherited Destroy;
end;

{ TClientHandlerThread }

constructor TClientHandlerThread.Create(APipe: THandle; AOwner: TBaseService);
begin
  FOwner := AOwner;
  FreeOnTerminate := True;
  DCDebug('Connected success');
  FTransport:= TPipeTransport.Create(APipe, FOwner.ProcessID);
  inherited Create(False);
end;

{ TServerListnerThread }

constructor TServerListnerThread.Create(AOwner: TBaseService);
begin
  FEvent:= CreateEvent(nil, False, False, nil);
  inherited Create(AOwner);
end;

destructor TServerListnerThread.Destroy;
begin
  Terminate;
  SetEvent(FEvent);
  inherited Destroy;
  CloseHandle(FEvent);
end;

procedure TServerListnerThread.Execute;
var
  SID: TBytes;
  dwWait: DWORD;
  hPipe: THandle;
  ACL: PACL = nil;
  bPending: Boolean;
  AName: UnicodeString;
  Overlapped: TOverlapped;
  SA: TSecurityAttributes;
  SD: TSecurityDescriptor;
  Events: array[0..1] of THandle;
  ExplicitAccess: TExplicitAccess;
begin
  AName:= UTF8Decode(FOwner.Name);

  if not GetCurrentUserSID(SID) then Halt;

  ZeroMemory(@ExplicitAccess, SizeOf(ExplicitAccess));
  with ExplicitAccess do
  begin
    grfAccessPermissions:= GENERIC_ALL;
    grfAccessMode:= DWORD(SET_ACCESS);
    grfInheritance:= NO_INHERITANCE;
    Trustee.TrusteeForm:= DWORD(TRUSTEE_IS_SID);
    Trustee.TrusteeType:= DWORD(TRUSTEE_IS_USER);
    Trustee.ptstrName:= PAnsiChar(@SID[0]);
  end;

  if SetEntriesInAcl(1, @ExplicitAccess, nil, JwaWinNT.PACL(ACL)) <> ERROR_SUCCESS then
    Halt;
  if not InitializeSecurityDescriptor (@SD, SECURITY_DESCRIPTOR_REVISION) then
    Halt;
  if not SetSecurityDescriptorDacl(@SD, True, ACL, False) then
    Halt;

  ZeroMemory(@Overlapped, SizeOf(TOverlapped));

  Overlapped.hEvent:= CreateEvent(nil, True, True, nil);

  Events[0]:= Overlapped.hEvent;
  Events[1]:= FEvent;

  while not Terminated do
  begin
    SA.nLength := SizeOf(SA);
    SA.lpSecurityDescriptor := @SD;
    SA.bInheritHandle := True;

    // Create pipe server
    hPipe := CreateNamedPipeW(PWideChar('\\.\pipe\' + AName),
      PIPE_ACCESS_DUPLEX or
      FILE_FLAG_OVERLAPPED,
      PIPE_WAIT or
      PIPE_READMODE_BYTE or
      PIPE_TYPE_BYTE,
      PIPE_UNLIMITED_INSTANCES,
      maxSmallint,
      maxSmallint,
      0,
      @SA);

    if hPipe = INVALID_HANDLE_VALUE then
      Halt;

    DCDebug('Start server ', FOwner.Name);

    FReadyEvent.SetEvent;

    while not Terminated do
    begin
      bPending:= False;

      if not ConnectNamedPipe(hPipe, @Overlapped) then
      begin
        case (GetLastError()) of
        ERROR_IO_PENDING:
          bPending:= True;
        ERROR_PIPE_CONNECTED:
          SetEvent(Overlapped.hEvent);
        else
          begin
            DisconnectNamedPipe(hPipe);
            Continue;
          end;
        end;
      end;

      // Wait client connection
      dwWait := WaitForMultipleObjectsEx(Length(Events), Events, False, INFINITE, True);

      if (dwWait = 1) or ((dwWait = 0) and bPending and (not GetOverlappedResult(hPipe, Overlapped, dwWait, False))) then
      begin
        DisconnectNamedPipe(hPipe);
        Continue;
      end;

      if (FOwner.VerifyChild and not VerifyChild(hPipe)) or
         (FOwner.VerifyParent and not VerifyParent(hPipe)) then
      begin
        DisconnectNamedPipe(hPipe);
        Continue;
      end;

      Break;
    end; // while

    if not Terminated then
      TClientHandlerThread.Create(hPipe, FOwner)
    else begin
      DisconnectNamedPipe(hPipe);
    end;
  end; // while

  CloseHandle(hPipe);
  CloseHandle(Events[0]);
  LocalFree(HLOCAL(ACL));
end;

end.

