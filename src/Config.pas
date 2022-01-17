unit Config;

{$MODE Delphi}

interface

uses SysUtils, Classes, WinSock;

const
  DFLT_COMMENTS = '#';
  DFLT_SEPARATOR = '=';
  SERVER_VERSION = 'Oxyde Server 0.2';
  DEFAULT_TIMEOUT = 5;
  DEFAULT_PORT = 80;
  DEFAULT_LISTEN = 10;

type
  pConfigItem = ^ConfigItem;
  ConfigItem = record
    Name, Value: string;
    Next: pConfigItem;
  end;

  { Classe contenant une liste chainée simple. On aurait pu utiliser une TStringList
    mais cette dernière ne supporte pas les espaces avant et après le signe '='. }
  ConfigFile = class(TObject)
  private
    Head: pConfigItem;

    { Vide completement la liste. }
    procedure Flush;
    { Renvoie un élément de la liste. }
    function FindItem(Name: string): pConfigItem;
    { Renvoie le contenu d'une valeur à partir de son nom. Utilise en interne FindItem. }
    function GetValue(Name: string): string;
    { Mais à jour le contenu d'une valeur. Utilise en interne FindItem. }
    procedure SetValue(Name, Value: string);
  public
    Separator, Comments: Char;
    property Value[Name: string]: string read GetValue write SetValue;

    { Charge une liste à partir d'un fichier. }
    function LoadFromFile(CfgFile: string): Integer;
    { Indique si la liste est vide ou non. }
    function IsEmpty: Boolean;
    { Indique si une valeur existe pour le nom passé en paramètre. }
    function Exits(Name: string): Boolean;

    constructor Create;
    { Constructeur supplémentaire qui éffectue le chargement directement. }
    constructor CreateAndLoad(CfgFile: string);
    destructor Destroy; override;
  end;

  { Structure contenant les paramètres du serveur }
  ServerParams = record
    { Paramètres généraux }
    Version: string;        { Version du serveur }
    DocumentRoot: string;   { Répertoire de base du site }
    DirectoryIndex: string; { Page par default }
    ErrorFile: string;      { Gestion des erreurs }
    Timeout: Integer;       { Temps en secondes pendant lequel on doit attendre une requete }
    Mime: ConfigFile;       { Correspondance extension/MIME }
    DefaultType: string;    { Type MIME par défaut }
    { Paramètres réseaux }
    NetAddr: TInAddr;       { Adresse IP de l'interface du serveur }
    Port: WORD;             { Numéro de port }
    Listen: Integer;        { File d'attente }
  end;
  pServerParams = ^ServerParams;

  function Init(cfgFile: string; var Params: ServerParams): Boolean;

implementation

{__________________________________________________________________________________________

 Initialisation du serveur
 __________________________________________________________________________________________}


{ Charge la structure Params à partir du fichier cfgFile }

function Init(cfgFile: string; var Params: ServerParams): Boolean;
var
  cfgServer: ConfigFile;
  Code: Integer;
begin
  Result := False;

  cfgServer := ConfigFile.CreateAndLoad(cfgFile);
  try
    if cfgServer.IsEmpty then
      Writeln('Error : Init() ' + cfgFile + ' read error')
    else
      with Params do begin
        { Récupération et construction des paramètres }
        Version := SERVER_VERSION;

        DocumentRoot := cfgServer.Value['DocumentRoot'];
        if DocumentRoot = '' then Exit;

        DirectoryIndex := cfgServer.Value['DirectoryIndex'];
        ErrorFile := cfgServer.Value['ErrorFile'];

        Val(cfgServer.Value['Timeout'], Timeout, Code);
        if Code <> 0 then
          Timeout := DEFAULT_TIMEOUT;

        Mime := ConfigFile.CreateAndLoad(ExtractFilePath(ParamStr(0)) +
                                         cfgServer.Value['TypesConfig']);

        DefaultType := cfgServer.Value['DefaultType'];

        { Configuration réseau }
        NetAddr.S_addr := inet_addr(PChar(cfgServer.Value['Interface']));
        if NetAddr.S_addr = INADDR_NONE then
          NetAddr.S_addr := INADDR_ANY;

        Val(cfgServer.Value['Port'], Port, Code);
        if Code <> 0 then
          Port := DEFAULT_PORT;

        Val(cfgServer.Value['Listen'], Listen, Code);
        if Code <> 0 then
          Listen := DEFAULT_LISTEN;

        Result := True;  
      end;
  finally
    cfgServer.Free();
  end;
end;

{__________________________________________________________________________________________

 ConfigFile
 __________________________________________________________________________________________}

{ Renvoie un pointeur sur un élément dont la propriété Name correspond au paramètre  }

function ConfigFile.FindItem(Name: string): pConfigItem;
begin
  Result := Head;
  while (Result <> nil) and (Result^.Name <> Name) do
    Result := Result^.Next;
end;

{ Renvoie la valeur d'un paramètre de configuration }

function ConfigFile.GetValue(Name: string): string;
var
  tmpItem: pConfigItem;
begin
  tmpItem := FindItem(Name);
  if tmpItem <> nil then
    Result := tmpItem^.Value
  else
    Result := '';
end;

{ Met à jour un paramètre }

procedure ConfigFile.SetValue(Name, Value: string);
var
  tmpItem: pConfigItem;
begin
  tmpItem := FindItem(Name);
  if tmpItem <> nil then
    tmpItem^.Value := Value;
end;

{ Charge la liste à partir d'un fichier }

function ConfigFile.LoadFromFile(CfgFile: string): Integer;
var
  iFile: TextFile;
  line: string;
  k: Integer;
  Item: pConfigItem;
begin
  Result := 0;

  {$I-}
  AssignFile(iFile, CfgFile);
  FileMode := 0;  { Lecture seule }
  Reset(iFile);
  {$I+}

  if IOResult = 0 then begin

    { On vide la liste avant tout }
    Flush();

    while not Eof(iFile) do begin
      Readln(iFile, line);

      line := Trim(line);
      if (Line <> '') and (Line[1] <> Comments) then begin

        k := Pos(Separator, Line);
        if k = 0 then k := MaxInt - 1;
        New(Item);
        Item^.Name := TrimRight(Copy(Line, 1, k - 1));
        Item^.Value := TrimLeft(Copy(Line, k + 1, MaxInt));
        Item^.Next := Head;
        Head := Item;
        Inc(Result);

      end;
    end;
  end;

  {$I-}
  CloseFile(iFile);
  {$I+}
end;

{ Indique si la liste est vide ou pas }

function ConfigFile.IsEmpty: Boolean;
begin
  Result := (Head = nil);
end;

{ Permet de savoir si un paramètre existe }

function ConfigFile.Exits(Name: string): Boolean;
begin
  Result := (FindItem(Name) <> nil);
end;

{ Vide la liste de ses éléments }

procedure ConfigFile.Flush;
var
  tmpItem: pConfigItem;
begin
  while Head <> nil do begin
    tmpItem := Head;
    Head := Head^.Next;
    Dispose(tmpItem);
  end;
end;

constructor ConfigFile.Create;
begin
  inherited Create();
  Head := nil;
  Comments := DFLT_COMMENTS;
  Separator := DFLT_SEPARATOR;
end;

constructor ConfigFile.CreateAndLoad(CfgFile: string);
begin
  Create();              { On appelle le constructeur par défault ... }
  LoadFromFile(CfgFile); { ... et on charge le fichier de configuration }
end;

destructor ConfigFile.Destroy;
begin
  Flush();
  inherited Destroy();
end;

end.
