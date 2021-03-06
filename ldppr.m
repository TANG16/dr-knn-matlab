function [bestB, bestP, bestPP, info, other] = ldppr(X, XX, B0, P0, PP0, varargin)
%
% LDPPR: Learning Discriminative Projections and Prototypes for Regression
%
% Usage:
%   [B, P, PP] = ldppr(X, XX, B0, P0, PP0, ...)
%
% Usage initialize prototypes:
%   [P0, PP0] = ldppr('initP', X, XX, Np)
%
% Usage cross-validation (PCA & kmeans initialization):
%   [B, P, PP] = ldppr(X, XX, maxDr, maxNp, [], ...)
%
% Input:
%   X       - Independent training data. Each column vector is a data point.
%   XX      - Dependent training data.
%   B0      - Initial projection base.
%   P0      - Initial independent prototype data.
%   PP0     - Initial dependent prototype data.
%   maxDr   - Maximum reduced dimensionality.
%   maxNp   - Maximum number of prototypes.
%
% Output:
%   B       - Final learned projection base.
%   P       - Final learned independent prototype data.
%   PP      - Final learned dependent prototype data.
%
% Learning options:
%   'slope',SLOPE              - Tanh slope (default=1)
%   'rateB',RATEB              - Projection base learning rate (default=0.1)
%   'rateP',RATEP              - Ind. Prototypes learning rate (default=0.1)
%   'ratePP',RATEPP            - Dep. Prototypes learning rate (default=0)
%   'minI',MINI                - Minimum number of iterations (default=100)
%   'maxI',MAXI                - Maximum number of iterations (default=1000)
%   'epsilon',EPSILON          - Convergence criteria (default=1e-7)
%   'orthoit',OIT              - Orthogonalize every OIT (default=1)
%   'orthonormal',(true|false) - Orthonormal projection base (default=true)
%   'orthogonal',(true|false)  - Orthogonal projection base (default=false)
%   'dist',('euclidean'|       - Distance (default=euclidean)
%           'cosine'|            cosine
%           'rtangent'|          reference single sided tangent
%           'otangent'|          observation single sided tangent
%           'atangent')          average single sided tangent
%
% Data normalization options:
%   'normalize',(true|false)   - Normalize training data (default=true)
%   'linearnorm',(true|false)  - Linear normalize training data (default=false)
%
% Stochastic options:
%   'stochastic',(true|false)  - Stochastic gradient descend (default=true)
%   'stochsamples',SAMP        - Samples per stochastic iteration (default=10)
%   'stocheck',SIT             - Stats every SIT stoch. iterations (default=100)
%   'stocheckfull',(true|f...  - Stats for whole data set (default=false)
%   'stochfinalexact',(tru...  - Final stats for whole data set (default=true)
%
% Verbosity options:
%   'verbose',(true|false)     - Verbose (default=true)
%   'stats',STAT               - Statistics every STAT (default=10)
%   'logfile',FID              - Output log file (default=stderr)
%
% Tangent distances options:
%   'tangtypes'                - Tangent types [hvrspdtHV]+[k]K (default='k2')
%                                h: image horizontal translation
%                                v: image vertical translation
%                                r: image rotation
%                                s: image scaling
%                                p: image parallel hyperbolic transformation
%                                d: image diagonal hyperbolic transformation
%                                t: image trace thickening
%                                H: image horizontal illumination
%                                V: image vertical illumination
%                                k: K nearest neighbors
%   'imSize',[W H]             - Image size (default=square)
%   'bw',BW                    - Tangent derivative gaussian bandwidth (default=0.5)
%   'krh',KRH                  - Supply tangent derivative kernel, horizontal
%   'krv',KRV                  - Supply tangent derivative kernel, vertical
%
% Other options:
%   'devel',Y,YY               - Set the development set (default=false)
%   'seed',SEED                - Random seed (default=system)
%
% Cross-validation options:
%   'crossvalidate',K          - Do K-fold cross-validation (default=2)
%   'cv_slope',[SLOPES]        - Slopes to try (default=[10])
%   'cv_Np',[NPs]              - Prototypes to try (default=[2.^[1:4]])
%   'cv_Dr',[DRs]              - Reduced dimensions to try (default=[2.^[2:5]])
%   'cv_rateB',[RATEBs]        - B learning rates to try (default=[10.^[-2:0]])
%   'cv_rateP',[RATEPs]        - P learning rates to try (default=[10.^[-2:0]])
%   'cv_ratePP',[RATEPPs]      - PP learning rates to try (default=[0])
%   'cv_save',(true|false)     - Save cross-validation results (default=false)
%
%
% $Revision$
% $Date$
%

%
% Copyright (C) 2008-2010 Mauricio Villegas <mauvilsa@upv.es>
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program. If not, see <http://www.gnu.org/licenses/>.
%

if strncmp(X,'-v',2),
  unix('echo "$Revision$* $Date$*" | sed "s/^:/ldppr: revision/g; s/ : /[/g; s/ (.*)/]/g;"');
  return;
end

if strncmp(X,'initP',5),
  if ~exist('PP0','var'),
    [bestB, bestP] = ldppr_initP(XX, B0, P0);
  else
    [bestB, bestP] = ldppr_initP(XX, B0, P0, PP0, varargin{:});
  end
  return;
end

fn='ldppr:';
minargs=5;

%%% Default values %%%
bestB=[];
bestP=[];
bestPP=[];

slope=1;
rateB=0.1;
rateP=0.1;
ratePP=0;

epsilon=1e-7;
minI=100;
maxI=1000;
stats=10;
orthoit=1;

devel=false;
stochastic=false;
stochsamples=10;
stocheck=100;
stocheckfull=false;
stochfinalexact=true;
orthonormal=true;
orthogonal=false;
dtype.euclidean=true;
dtype.cosine=false;
dtype.tangent=false;
dtype.rtangent=false;
dtype.otangent=false;
dtype.atangent=false;
tangtypes='k2';
normalize=true;
linearnorm=false;
testJ=false;
indepPP=true;
MAD=false;
crossvalidate=false;
cv_save=false;

logfile=2;
verbose=true;

%%% Input arguments parsing %%%
n=1;
argerr=false;
while size(varargin,2)>0,
  if ~ischar(varargin{n}) || size(varargin,2)<n+1,
    argerr=true;
  elseif strcmp(varargin{n},'probemode'),
    eval([varargin{n},'=varargin{n+1};']);
    n=n+2;
  elseif strcmp(varargin{n},'slope') || ...
         strcmp(varargin{n},'rates') || ...
         strcmp(varargin{n},'rateB') || ...
         strcmp(varargin{n},'rateP')  || ...
         strcmp(varargin{n},'ratePP')  || ...
         strcmp(varargin{n},'epsilon') || ...
         strcmp(varargin{n},'minI') || ...
         strcmp(varargin{n},'maxI') || ...
         strcmp(varargin{n},'stats') || ...
         strcmp(varargin{n},'seed') || ...
         strcmp(varargin{n},'stochsamples') || ...
         strcmp(varargin{n},'stocheck') || ...
         strcmp(varargin{n},'orthoit') || ...
         strcmp(varargin{n},'crossvalidate') || ...
         strcmp(varargin{n},'cv_slope') || ...
         strcmp(varargin{n},'cv_Np') || ...
         strcmp(varargin{n},'cv_Dr') || ...
         strcmp(varargin{n},'cv_rateB') || ...
         strcmp(varargin{n},'cv_rateP') || ...
         strcmp(varargin{n},'cv_ratePP') || ...
         strcmp(varargin{n},'imSize') || ...
         strcmp(varargin{n},'bw') || ...
         strcmp(varargin{n},'krh') || ...
         strcmp(varargin{n},'krv') || ...
         strcmp(varargin{n},'logfile'),
    eval([varargin{n},'=varargin{n+1};']);
    if ~isnumeric(varargin{n+1}) || sum(sum(varargin{n+1}<0))~=0,
      argerr=true;
    else
      n=n+2;
    end
  elseif strcmp(varargin{n},'orthonormal') || ...
         strcmp(varargin{n},'orthogonal') || ...
         strcmp(varargin{n},'normalize') || ...
         strcmp(varargin{n},'linearnorm') || ...
         strcmp(varargin{n},'stochastic') || ...
         strcmp(varargin{n},'stocheckfull') || ...
         strcmp(varargin{n},'stochfinalexact') || ...
         strcmp(varargin{n},'testJ') || ...
         strcmp(varargin{n},'cv_save') || ...
         strcmp(varargin{n},'indepPP') || ...
         strcmp(varargin{n},'MAD') || ...
         strcmp(varargin{n},'verbose'),
    eval([varargin{n},'=varargin{n+1};']);
    if ~islogical(varargin{n+1}),
      argerr=true;
    else
      if varargin{n+1}==true,
        if strcmp(varargin{n},'orthonormal'),
          orthogonal=false;
        elseif strcmp(varargin{n},'orthogonal'),
          orthonormal=false;
        elseif strcmp(varargin{n},'normalize'),
          linearnorm=false;
        elseif strcmp(varargin{n},'linearnorm'),
          normalize=false;
        end
      end
      n=n+2;
    end
  elseif strcmp(varargin{n},'tangtypes'),
    eval([varargin{n},'=varargin{n+1};']);
    if ~ischar(varargin{n+1}),
      argerr=true;
    else
      n=n+2;
    end
  elseif strcmp(varargin{n},'dist') && ( ...
         strcmp(varargin{n+1},'euclidean') || ...
         strcmp(varargin{n+1},'rtangent') || ...
         strcmp(varargin{n+1},'otangent') || ...
         strcmp(varargin{n+1},'atangent') || ...
         strcmp(varargin{n+1},'cosine') ),
    dtype.euclidean=false;
    dtype.cosine=false;
    dtype.rtangent=false;
    dtype.otangent=false;
    dtype.atangent=false;
    eval(['dtype.',varargin{n+1},'=true;']);
    n=n+2;
  elseif strcmp(varargin{n},'devel'),
    devel=true;
    Y=varargin{n+1};
    YY=varargin{n+2};
    n=n+3;
  else
    argerr=true;
  end
  if argerr || n>size(varargin,2),
    break;
  end
end

DD=size(XX,1);
[D,Nx]=size(X);
if devel,
  Ny=size(Y,2);
end

%%% Automatic initial parameters %%%
if ~crossvalidate && max(size(B0))==1 && max(size(P0))==1,
  crossvalidate=2;
end
if max(size(B0))==1,
  if ~crossvalidate,
    Bi=pca(X);
    B0=Bi(:,1:min(B0,D));
  else
    B0=rand(D,min(B0,D));
  end
end
if max(size(P0))==1,
  if ~crossvalidate,
    [P0,PP0]=ldppr_initP(X,XX,P0);
  else
    PP0=zeros(DD,P0);
    P0=rand(D,P0);
  end
end

Dr=size(B0,2);
Np=size(P0,2);

%%% Probe mode %%%
if exist('probemode','var'),
  probevars=fieldnames(probemode);
  for n=1:size(probevars,1),
    eval([probevars{n} '=probemode.' probevars{n} ';']);
  end
  normalize=false;
  verbose=true;
  probemode=true;
  xxsd=ones(DD,1);
else
  probemode=false;
  if crossvalidate,
    if ~exist('cv_slope','var'),
      cv_slope=slope;
    end
    if ~exist('cv_Np','var'),
      cv_Np=[2.^[1:4]];
      cv_Np(cv_Np>=Np)=[];
      cv_Np=[cv_Np,Np];
    end
    if ~exist('cv_Dr','var'),
      cv_Dr=[2.^[2:5]];
      cv_Dr(cv_Dr>=Dr)=[];
      cv_Dr=[cv_Dr,Dr];
    end
    if ~exist('cv_rateB','var'),
      cv_rateB=[10.^[-2:0]];
    end
    if ~exist('cv_rateP','var'),
      cv_rateP=[10.^[-2:0]];
    end
    if ~exist('cv_ratePP','var'),
      cv_ratePP=ratePP;
    end
  end
end

%%% Error detection %%%
if probemode,
elseif argerr,
  fprintf(logfile,'%s error: incorrect input argument %d (%s,%g)\n',fn,n+minargs,varargin{n},varargin{n+1});
  return;
elseif nargin-size(varargin,2)~=minargs,
  fprintf(logfile,'%s error: not enough input arguments\n',fn);
  return;
elseif size(B0,1)~=D || size(P0,1)~=D,
  fprintf(logfile,'%s error: dimensionality of base, prototypes and data must be the same\n',fn);
  return;
elseif size(XX,2)~=Nx || size(PP0,2)~=Np,
  fprintf(logfile,'%s error: the number of vectors in the dependent and independent data must be the same\n',fn);
  return;
elseif size(PP0,1)~=DD,
  fprintf(logfile,'%s error: the dimensionality of the dependent variables for the data and the prototypes must be the same\n',fn);
  return;
end

if ~verbose,
  logfile=fopen('/dev/null');
end

%%% Preprocessing %%%
if ~probemode,
  tic;

  B0=double(B0);
  P0=double(P0);

  if exist('seed','var'),
    rand('state',seed);
  end

  if exist('rates','var'),
    rateB=rates;
    rateP=rates;
  end

  onesNx=ones(Nx,1);
  onesNp=ones(Np,1);
  onesDr=ones(Dr,1);
  onesDD=ones(DD,1);
  if devel,
    onesNy=ones(Ny,1);
  end

  %%% Normalization %%%
  oX=X;
  if devel,
    oY=Y;
  end
  if normalize || linearnorm,
    xmu=mean(X,2);
    xsd=std(X,1,2);
    % xsd=sqrt(D*Dr)*xsd/10;
    xsd=Dr*xsd; % this needs to be tested !!!
    if linearnorm,
      xsd=max(xsd)*ones(size(xsd));
    end
    if issparse(X) && ~dtype.cosine,
      xmu=full(xmu);
      xsd=full(xsd);
      X=X./xsd(:,onesNx);
      if devel,
        Y=Y./xsd(:,onesNy);
      end
      P0=P0./xsd(:,onesNp);
    else
      X=(X-xmu(:,onesNx))./xsd(:,onesNx);
      if devel,
        Y=(Y-xmu(:,onesNy))./xsd(:,onesNy);
      end
      P0=(P0-xmu(:,onesNp))./xsd(:,onesNp);
    end
    B0=B0.*xsd(:,onesDr);
    if sum(xsd==0)>0,
      X(xsd==0,:)=[];
      if devel,
        Y(xsd==0,:)=[];
      end
      B0(xsd==0,:)=[];
      P0(xsd==0,:)=[];
      fprintf(logfile,'%s warning: some dimensions have a standard deviation of zero\n',fn);
    end
  end

  xxmu=mean(XX,2);
  xxsd=std(XX,1,2);
  xxsd=DD*xxsd;
  XX=(XX-xxmu(:,onesNx))./xxsd(:,onesNx);
  if devel,
    YY=(YY-xxmu(:,onesNy))./xxsd(:,onesNy);
  end
  PP0=(PP0-xxmu(:,onesNp))./xxsd(:,onesNp);
  if ~MAD,
    xxsd=xxsd.*xxsd;
  end

  %%% Tangent vectors %%%
  if dtype.rtangent || dtype.otangent || dtype.atangent,
    dtype.tangent=true;
    tangcfg.imgtangcfg=struct;
    if exist('imSize','var'),
      tangcfg.imgtangcfg.imSize=imSize;
    end
    if exist('bw','var'),
      tangcfg.imgtangcfg.bw=bw;
    end
    if exist('krh','var'),
      tangcfg.imgtangcfg.krh=krh;
    end
    if exist('krv','var'),
      tangcfg.imgtangcfg.krv=krv;
    end
    tangcfg.imgtangs=false;
    tangcfg.knntangs=false;
    tangcfg.devel=devel;
    tangcfg.dtype=dtype;
    tangcfg.onesNp=onesNp;
    tangcfg.Np=Np;
    tangcfg.D=D;
    tangcfg.Vx=[];
    tangcfg.Vp=[];
    tangcfg.Vy=[];
    %%% k-NN tangents %%%
    if sum(tangtypes=='k')>0,
      idx=find(tangtypes=='k');
      tangcfg.knntangs=str2num(tangtypes(idx+1:end));
      tangcfg.knntypes=tangtypes(idx:end);
      tangtypes=tangtypes(1:idx-1);
      %tangcfg.Xlabels=Xlabels;
      %tangcfg.Plabels=Plabels;
      %if devel,
      %  tangcfg.Ylabels=Ylabels;
      %end
    end
    %%% Image tangents %%%
    if numel(tangtypes)>0,
      tangcfg.imgtangs=numel(tangtypes);
      tangcfg.imgtypes=tangtypes;
      tangcfg.normalize=normalize;
      tangcfg.linearnorm=linearnorm;
      if dtype.rtangent || dtype.atangent,
        if normalize || linearnorm,
          tangcfg.xmu=xmu;
          tangcfg.xsd=xsd;
        end
        if tangcfg.knntangs,
          tangcfg.knntangsp=repmat([false(tangcfg.imgtangs,1);true(tangcfg.knntangs,1)],1,Np);
          tangcfg.knntangsp=tangcfg.knntangsp(:);
          tangcfg.Vp=zeros(Dr,numel(tangcfg.knntangsp));
        end
      end
      if dtype.otangent || dtype.atangent,
        tangcfg.oVx=tangVects(oX,tangcfg.imgtypes,tangcfg.imgtangcfg);
        if normalize || linearnorm,
          tangcfg.oVx=(tangcfg.oVx-xmu(:,ones(size(tangcfg.oVx,2),1)))./xsd(:,ones(size(tangcfg.oVx,2),1));
          if sum(xsd==0)>0,
            tangcfg.oVx(xsd==0,:)=[];
          end
        end
        if tangcfg.knntangs,
          tangcfg.knntangsx=repmat([false(tangcfg.imgtangs,1);true(tangcfg.knntangs,1)],1,Nx);
          tangcfg.knntangsx=tangcfg.knntangsx(:);
          tangcfg.Vx=zeros(Dr,numel(tangcfg.knntangsx));
        end
        if devel,
          tangcfg.oVy=tangVects(oY,tangcfg.imgtypes,tangcfg.imgtangcfg);
          if normalize || linearnorm,
            tangcfg.oVy=(tangcfg.oVy-xmu(:,ones(size(tangcfg.oVy,2),1)))./xsd(:,ones(size(tangcfg.oVy,2),1));
            if sum(xsd==0)>0,
              tangcfg.oVy(xsd==0,:)=[];
            end
          end
          if tangcfg.knntangs,
            tangcfg.knntangsy=repmat([false(tangcfg.imgtangs,1);true(tangcfg.knntangs,1)],1,Ny);
            tangcfg.knntangsy=tangcfg.knntangsy(:);
            tangcfg.Vy=zeros(Dr,numel(tangcfg.knntangsy));
          end
        end
      end
    end
    tangcfg.L=tangcfg.knntangs+tangcfg.imgtangs;
  end

  %%% Stochastic preprocessing %%%
  if stochastic,
    orthoit=orthoit*stocheck;
    minI=minI*stocheck;
    maxI=maxI*stocheck;
    stats=stats*stocheck;
  end

  %%% Initial parameter constraints %%%
  if orthonormal,
    B0=orthonorm(B0);
  elseif orthogonal,
    B0=orthounit(B0);
  end

  %%% Constant data structures %%%
  [work.ind1,work.ind2]=comp_ind(DD,Np,Nx,onesNx);
  work.slope=slope;
  work.onesDr=onesDr;
  work.onesNp=onesNp;
  work.onesNx=onesNx;
  work.onesDD=onesDD;
  work.xxsd=xxsd;
  work.Np=Np;
  work.Nx=Nx;
  work.DD=DD;
  work.Dr=Dr;
  work.dtype=dtype;
  work.indepPP=indepPP;
  work.MAD=MAD;
  if dtype.tangent,
    work.L=tangcfg.L;
    if dtype.otangent || dtype.atangent,
      work.tidx=repmat([1:Nx],work.L,1);
      work.tidx=work.tidx(:);
    end
  end

  if stochastic,
    swork=work;
    onesS=ones(stochsamples,1);
    [swork.ind1,swork.ind2]=comp_ind(DD,Np,stochsamples,onesS);
    swork.onesNx=onesS;
    swork.onesNp=onesNp;
    swork.Nx=stochsamples;
  end

  if devel,
    dwork=work;
    [dwork.ind1,dwork.ind2]=comp_ind(DD,Np,Ny,onesNy);
    dwork.Nx=Ny;
    dwork.onesNx=onesNy;
    if dtype.tangent,
      dwork.L=tangcfg.L;
      if dtype.otangent || dtype.atangent,
        dwork.tidx=repmat([1:Ny],work.L,1);
        dwork.tidx=dwork.tidx(:);
      end
    end
  end

  etype='RMSE';
  if MAD,
    etype='MAD';
  end

  tm=toc;
  info.time=tm;
  fprintf(logfile,'%s total preprocessing time (s): %f\n',fn,tm);
end

%%% Cross-validaton %%%
if crossvalidate,
  tic;

  cv_Ny=floor(Nx/crossvalidate);
  cv_Nx=cv_Ny*(crossvalidate-1);

  %%% Generate cross-validation partitions %%%
  [v,cv_rnd]=sort(rand(Nx,1));
  cv_rnd=cv_rnd(1:cv_Ny*crossvalidate);

  Bi=pca(X);
  Bi=Bi(:,1:min(D,32));

  %%% Constant data structures %%%
  cv_onesNx=ones(cv_Nx,1);
  cv_onesNy=ones(cv_Ny,1);

  cv_wk=work;
  cv_wk.Nx=cv_Nx;
  cv_wk.onesNx=cv_onesNx;

  cv_dwk=work;
  cv_dwk.Nx=cv_Ny;
  cv_dwk.onesNx=cv_onesNy;

  if stochastic,
    cv_swk=swork;
  end

  if dtype.tangent,
    if dtype.otangent || dtype.atangent,
      cv_wk.tidx=repmat([1:cv_Nx],work.L,1);
      cv_wk.tidx=cv_wk.tidx(:);
      cv_dwk.tidx=repmat([1:cv_Ny],work.L,1);
      cv_dwk.tidx=cv_dwk.tidx(:);
    end
  end

  cv_cfg.minI=minI;
  cv_cfg.maxI=maxI;
  cv_cfg.epsilon=epsilon;
  cv_cfg.stats=maxI+1;
  cv_cfg.orthoit=orthoit;
  cv_cfg.orthonormal=orthonormal;
  cv_cfg.orthogonal=orthogonal;
  cv_cfg.dtype=dtype;
  if dtype.tangent,
    cv_cfg.tangcfg=tangcfg;
    cv_cfg.tangcfg.devel=true;
  end
  cv_cfg.testJ=testJ;
  cv_cfg.stochastic=stochastic;
  cv_cfg.devel=true;
  cv_cfg.onesDD=onesDD;
  if stochastic,
    cv_cfg.stochsamples=stochsamples;
    cv_cfg.stocheck=stocheck;
    cv_cfg.stocheckfull=stocheckfull;
    cv_cfg.stochfinalexact=stochfinalexact;
  end
  cv_cfg.logfile=fopen('/dev/null');

  Nparam=numel(cv_slope)*numel(cv_Np)*numel(cv_Dr)*numel(cv_rateB)*numel(cv_rateP)*numel(cv_ratePP);
  cv_E=zeros(Nparam,1);
  cv_I=zeros(Nparam,1);

  %%% Perform cross-validation %%%
  for v=1:crossvalidate,
    cv_Xrnd=cv_rnd;
    cv_Xrnd((v-1)*cv_Ny+1:v*cv_Ny)=[];
    cv_Xrnd=sort(cv_Xrnd);
    cv_Yrnd=cv_rnd((v-1)*cv_Ny+1:v*cv_Ny);
    cv_Yrnd=sort(cv_Yrnd);
    cv_X=X(:,cv_Xrnd);
    cv_XX=XX(:,cv_Xrnd);

    cv_cfg.Y=X(:,cv_Yrnd);
    cv_cfg.YY=XX(:,cv_Yrnd);

    if dtype.tangent,
      if dtype.otangent || dtype.atangent,
        sel=(repmat((cv_Xrnd-1)*work.L+1,1,work.L)+repmat([0:work.L-1],cv_Nx,1))';
        cv_cfg.tangcfg.oVx=tangcfg.oVx(:,sel(:));
        sel=(repmat((cv_Yrnd-1)*work.L+1,1,work.L)+repmat([0:work.L-1],cv_Ny,1))';
        cv_cfg.tangcfg.oVy=tangcfg.oVx(:,sel(:));
      end
    end

    %%% Vary the slope %%%
    param=1;
    for slope=cv_slope,
      cv_wk.slope=slope;
      cv_dwk.slope=slope;
      if stochastic,
        cv_swk.slope=slope;
      end

      %%% Vary the number of prototypes %%%
      for Np=cv_Np,

        [P0,PP0]=ldppr_initP(cv_X,cv_XX,Np);
        [cv_wk.ind1,cv_wk.ind2]=comp_ind(DD,Np,cv_Nx,cv_onesNx);
        [cv_dwk.ind1,cv_dwk.ind2]=comp_ind(DD,Np,cv_Nx,cv_onesNy);
        cv_wk.onesNp=onesNp;
        cv_dwk.onesNp=onesNp;
        cv_wk.Np=Np;
        cv_dwk.Np=Np;

        if stochastic,
          [cv_swk.ind1,cv_swk.ind2]=comp_ind(DD,Np,stochsamples,onesS);
          cv_swk.Np=Np;
          cv_swk.onesNp=onesNp;
        end

        %%% Vary the reduced dimensionality %%%
        for Dr=cv_Dr,
          B0=Bi(:,1:Dr);
          onesDr=ones(Dr,1);
          cv_cfg.onesDr=onesDr;

          cv_wk.Dr=Dr;
          cv_wk.onesDr=onesDr;
          cv_dwk.Dr=Dr;
          cv_dwk.onesDr=onesDr;
          cv_cfg.work=cv_wk;
          cv_cfg.dwork=cv_dwk;
          if stochastic,
            cv_swk.Dr=Dr;
            cv_swk.onesDr=onesDr;
            cv_cfg.swork=cv_swk;
          end

          fprintf(logfile,'%s cv %d: slope=%g Np=%d Dr=%d ',fn,v,slope,Np,Dr);

          %%% Vary learning rates %%%
          for rateB=cv_rateB,
            cv_cfg.rateB=rateB;
            for rateP=cv_rateP,
              cv_cfg.rateP=rateP;
              for ratePP=cv_ratePP,
                cv_cfg.ratePP=ratePP;

                [I,E]=ldppr(cv_X,cv_XX,B0,P0,PP0,'probemode',cv_cfg);
                cv_E(param)=cv_E(param)+E;
                cv_I(param)=cv_I(param)+I;
                cv_param{param}.slope=slope;
                cv_param{param}.Np=Np;
                cv_param{param}.Dr=Dr;
                cv_param{param}.rateB=rateB;
                cv_param{param}.rateP=rateP;
                cv_param{param}.ratePP=ratePP;
                param=param+1;
                fprintf(logfile,'.');
              end
            end
          end
          fprintf(logfile,'\n');
        end
      end
    end
  end

  cv_E=cv_E./crossvalidate;
  cv_I=cv_I./crossvalidate;
  param=find(min(cv_E)==cv_E,1);
  if cv_save,
    save('ldppr_cv.mat','cv_E','cv_I','cv_param');
  end
  info.cv_E=cv_E;
  info.cv_impI=cv_I;
  info.cv_param=cv_param;

  %%% Get best cross-validaton parameters %%%
  slope=cv_param{param}.slope;
  Np=cv_param{param}.Np;
  Dr=cv_param{param}.Dr;
  rateB=cv_param{param}.rateB;
  rateP=cv_param{param}.rateP;
  ratePP=cv_param{param}.ratePP;
  onesDr=ones(Dr,1);
  onesNp=ones(Np,1);

  B0=Bi(:,1:Dr);
  [P0,PP0]=ldppr_initP(X,XX,Np);
  [work.ind1,work.ind2]=comp_ind(DD,Np,Nx,ones(Nx,1));

  work.slope=slope;
  work.onesDr=onesDr;
  work.onesNp=onesNp;
  work.Np=Np;
  work.Dr=Dr;
  if stochastic,
    [swork.ind1,swork.ind2]=comp_ind(DD,Np,stochsamples,onesS);
    swork.slope=slope;
    swork.onesDr=onesDr;
    swork.onesNp=onesNp;
    swork.Np=Np;
    swork.Dr=Dr;
  end
  if devel,
    [dwork.ind1,dwork.ind2]=comp_ind(DD,Np,Ny,ones(Ny,1));
    dwork.slope=slope;
    dwork.onesDr=onesDr;
    dwork.onesNp=onesNp;
    dwork.Np=Np;
    dwork.Dr=Dr;
  end

  cv_test='E';
  if testJ,
    cv_test='J';
  end

  tm=toc;
  info.time=info.time+tm;
  fprintf(logfile,'%s cv best statistics: %s=%g impI=%g\n',fn,cv_test,cv_E(param),cv_I(param));
  fprintf(logfile,'%s cv best parameters: slope=%g Np=%d Dr=%d rateB=%g rateP=%g ratePP=%g\n',fn,slope,Np,Dr,rateB,rateP,ratePP);
  fprintf(logfile,'%s total cross-validation time (s): %f\n',fn,tm);

  fclose(cv_cfg.logfile);
  clear cv_*;
end

if dtype.euclidean,
  rateB=2*rateB;
  rateP=2*rateP;
  ratePP=2*ratePP;
end
slope=slope/DD;
rateB=2*rateB*slope/Nx;
rateP=2*rateP*slope/Nx;
ratePP=2*ratePP*slope/Nx;

Bi=B0;
Pi=P0;
PPi=PP0;
bestB=B0;
bestP=P0;
bestPP=PP0;
bestIJE=[0 1 Inf -1];

J00=1;
J0=1;
I=0;

if ~probemode,
  fprintf(logfile,'%s Nx=%d Dx=%d Dxx=%d Dr=%d Np=%d\n',fn,Nx,D,DD,Dr,Np);
  fprintf(logfile,'%s output: iteration | J | delta(J) | %s\n',fn,etype);
  tic;
end

%%% Batch gradient descent %%%
if ~stochastic,

  while true,

    %%% Compute statistics %%%
    if work.dtype.tangent,
      fprintf(logfile,'%s error: tangent distances not implemented\n',fn);
      return;
    end
    rP=Bi'*Pi;
    rX=double(Bi'*X);
    if devel,
      rY=double(Bi'*Y);
    end
    if dtype.tangent,
      tangcfg.rP=rP;
      tangcfg.rX=rX;
      if devel,
        tangcfg.rY=rY;
      end
      tangcfg=comptangs(Bi,Pi,tangcfg);
      work.Vx=tangcfg.Vx;
      work.Vp=tangcfg.Vp;
      if devel,
        dwork.Vx=tangcfg.Vy;
        dwork.Vp=tangcfg.Vp;
      end
    end
    [E,J,fX,fP,fPP]=ldppr_index(rP,PPi,rX,XX,work);
    if devel,
      E=ldppr_index(rP,PPi,rY,YY,dwork);
    end

    %%% Determine if there was improvement %%%
    mark='';
    if (  testJ && (J<bestIJE(2)||(J==bestIJE(2)&&E<=bestIJE(3))) ) || ...
       ( ~testJ && (E<bestIJE(3)||(E==bestIJE(3)&&J<=bestIJE(2))) ),
      bestB=Bi;
      bestP=Pi;
      bestPP=PPi;
      bestIJE=[I J E bestIJE(4)+1];
      mark=' *';
    end

    %%% Print statistics %%%
    if mod(I,stats)==0,
      fprintf(logfile,'%d\t%.8f\t%.8f\t%.8f%s\n',I,J,J-J00,E,mark);
      J00=J;
    end

    %%% Determine if algorithm has to be stopped %%%
    if I>=maxI || ~isfinite(J) || ~isfinite(E) || (I>=minI && abs(J-J0)<epsilon),
      fprintf(logfile,'%s stopped iterating, ',fn);
      if I>=maxI,
        fprintf(logfile,'reached maximum number of iterations\n');
      elseif ~isfinite(J) || ~isfinite(E),
        fprintf(logfile,'reached unstable state\n');
      else
        fprintf(logfile,'index has stabilized\n');
      end
      break;
    end

    J0=J;
    I=I+1;

    %%% Update parameters %%%
    Bi=Bi-rateB.*(X*fX'+Pi*fP');
    Pi=Pi-rateP.*(Bi*fP);
    if indepPP,
      PPi=PPi-ratePP.*fPP;
    else
      PPi=PPi-ratePP.*fPP(onesDD,:);
    end

    %%% Parameter constraints %%%
    if mod(I,orthoit)==0,
      if orthonormal,
        Bi=orthonorm(Bi);
      elseif orthogonal,
        Bi=orthounit(Bi);
      end
    end

  end % while true

%%% Stochasitc gradient descent %%%
else

  prevJ=1;
  if devel,
    prevE=ldppr_index(Bi'*Pi,PPi,Bi'*Y,YY,dwork);
  else
    prevE=ldppr_index(Bi'*Pi,PPi,Bi'*X,XX,work);
  end

  while true,

    %%% Compute statistics %%%
    if mod(I,stocheck)==0 && stocheckfull,
      rP=Bi'*Pi;
      [E,J]=ldppr_index(rP,PPi,Bi'*X,XX,work);
      if devel,
        E=ldppr_index(rP,PPi,Bi'*Y,YY,dwork);
      end
    end

    %%% Select random samples %%%
    randn=round((Nx-1).*rand(stochsamples,1))+1; % modify for no repetitions
    sX=X(:,randn);

    %%% Compute statistics %%%
    if work.dtype.tangent,
      fprintf(logfile,'%s error: stochastic for tangent distances not implemented\n',fn);
      return;
    end
    [Ei,Ji,fX,fP,fPP]=ldppr_sindex(Bi'*Pi,PPi,Bi'*sX,XX(:,randn),swork);
    if ~stocheckfull,
      J=0.5*(prevJ+Ji);
      prevJ=J;
      if ~devel,
        E=0.5*(prevE+Ei);
        prevE=E;
      end
    end

    if mod(I,stocheck)==0,
      if ~stocheckfull && devel,
        E=ldppr_index(Bi'*Pi,PPi,Bi'*Y,YY,dwork);
      end

      %%% Determine if there was improvement %%%
      mark='';
      if (  testJ && (J<bestIJE(2)||(J==bestIJE(2)&&E<=bestIJE(3))) ) || ...
         ( ~testJ && (E<bestIJE(3)||(E==bestIJE(3)&&J<=bestIJE(2))) ),
        bestB=Bi;
        bestP=Pi;
        bestPP=PPi;
        bestIJE=[I J E bestIJE(4)+1];
        mark=' *';
      end

      %%% Print statistics %%%
      if mod(I,stats)==0,
        fprintf(logfile,'%d\t%.8f\t%.8f\t%.8f%s\n',I,J,J-J00,E,mark);
        J00=J;
      end

      %%% Determine if algorithm has to be stopped %%%
      if I>=maxI || ~isfinite(J) || ~isfinite(E) || (I>=minI && abs(J-J0)<epsilon),
        fprintf(logfile,'%s stopped iterating, ',fn);
        if I>=maxI,
          fprintf(logfile,'reached maximum number of iterations\n');
        elseif ~isfinite(J) || ~isfinite(E),
          fprintf(logfile,'reached unstable state\n');
        else
          fprintf(logfile,'index has stabilized\n');
        end
        break;
      end

      J0=J;
    end % if mod(I,stocheck)==0

    I=I+1;

    %%% Update parameters %%%
    Bi=Bi-rateB.*(sX*fX'+Pi*fP');
    Pi=Pi-rateP.*(Bi*fP);
    if indepPP,
      PPi=PPi-ratePP.*fPP;
    else
      PPi=PPi-ratePP.*fPP(onesDD,:);
    end

    %%% Parameter constraints %%%
    if mod(I,orthoit)==0,
      if orthonormal,
        Bi=orthonorm(Bi);
      elseif orthogonal,
        Bi=orthounit(Bi);
      end
    end

  end % while true

  %%% Parameter constraints %%%
  if orthonormal,
    bestB=orthonorm(bestB);
  elseif orthogonal,
    bestB=orthounit(bestB);
  end

  %%% Compute final statistics %%%
  if stochfinalexact && ~stocheckfull,
    [E,J]=ldppr_index(bestB'*bestP,bestPP,bestB'*X,XX,work);
    if devel,
      E=ldppr_index(bestB'*bestP,bestPP,bestB'*Y,YY,dwork);
    end

    fprintf(logfile,'%s best iteration approx: I=%d J=%f E=%f\n',fn,bestIJE(1),bestIJE(2),bestIJE(3));
    bestIJE(2)=J;
    bestIJE(3)=E;
  end % if stochfinalexact

end

if ~probemode,
  tm=toc;
  info.time=info.time+tm;
  info.E=bestIJE(3);
  info.J=bestIJE(2);
  info.I=bestIJE(1);
  info.impI=bestIJE(4)/max(I,1);
  fprintf(logfile,'%s best iteration: I=%d J=%f E=%f\n',fn,bestIJE(1),bestIJE(2),bestIJE(3));
  fprintf(logfile,'%s amount of improvement iterations: %f\n',fn,bestIJE(4)/max(I,1));
  fprintf(logfile,'%s average iteration time (ms): %f\n',fn,1000*tm/(I+0.5));
  fprintf(logfile,'%s total iteration time (s): %f\n',fn,tm);
end

if ~verbose,
  fclose(logfile);
end

if probemode,
  bestB=bestIJE(4)/max(I,1); % amount of improvement iterations
  if testJ,
    bestP=bestIJE(2); % optimization index
  else
    bestP=bestIJE(3); % error rate
  end
  return;
end

if nargout>4,
  other=struct;
  if dtype.tangent,
    tangcfg.rX=bestB'*X;
    tangcfg=comptangs(bestB,bestP,tangcfg);
    if dtype.otangent || dtype.atangent,
      other.Vx=tangcfg.Vx;
      if devel,
        other.Vy=tangcfg.Vy;
      end
    end
    if dtype.rtangent || dtype.atangent,
      other.Vp=tangcfg.Vp;
    end
  end
end

%%% Compensate for normalization in the final parameters %%%
if ~MAD,
  xxsd=sqrt(xxsd);
end
bestPP=bestPP.*xxsd(:,onesNp)+xxmu(:,onesNp);
if normalize || linearnorm,
  if issparse(X) && ~dtype.cosine,
    bestP=bestP.*xsd(xsd~=0,onesNp);
  else
    bestP=bestP.*xsd(xsd~=0,onesNp)+xmu(xsd~=0,onesNp);
  end
  bestB=bestB./xsd(xsd~=0,onesDr);
  if sum(xsd==0)>0,
    P=bestP;
    B=bestB;
    bestP=zeros(D,Np);
    bestP(xsd~=0,:)=P;
    bestB=zeros(D,Dr);
    bestB(xsd~=0,:)=B;
  end
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%                            Helper functions                             %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [E, J, fX, fP, fPP] = ldppr_index(P, PP, X, XX, work)

  Dr=work.Dr;
  DD=work.DD;
  Np=work.Np;
  Nx=work.Nx;
  onesDr=work.onesDr;
  onesDD=work.onesDD;
  ind1=work.ind1;
  ind2=work.ind2;

  %%% Compute distances %%%
  if work.dtype.euclidean,
    x2=sum((X.^2),1)';
    p2=sum((P.^2),1);
    dist=X'*P;
    dist=x2(:,work.onesNp)+p2(work.onesNx,:)-dist-dist;
  elseif work.dtype.cosine,
    psd=sqrt(sum(P.*P,1));
    P=P./psd(onesDr,:);
    xsd=sqrt(sum(X.*X,1));
    X=X./xsd(onesDr,:);
    dist=1-X'*P;
  elseif work.dtype.rtangent,
    dist=zeros(Nx,Np);
    nlp=1;
    for np=1:Np,
      dXP=X-P(:,np(work.onesNx));
      VdXP=work.Vp(:,nlp:nlp+work.L-1)'*dXP;
      dist(:,np)=(sum(dXP.*dXP,1)-sum(VdXP.*VdXP,1))';
      nlp=nlp+work.L;
    end
  elseif work.dtype.otangent,
    dist=zeros(Nx,Np);
    nlx=1;
    for nx=1:Nx,
      dXP=X(:,nx(work.onesNp))-P;
      VdXP=work.Vx(:,nlx:nlx+work.L-1)'*dXP;
      dist(nx,:)=sum(dXP.*dXP,1)-sum(VdXP.*VdXP,1);
      nlx=nlx+work.L;
    end
  elseif work.dtype.atangent,
    dist=zeros(Nx,Np);
    nlp=1;
    for np=1:Np,
      dXP=X-P(:,np(work.onesNx));
      VdXP=work.Vp(:,nlp:nlp+work.L-1)'*dXP;
      dist(:,np)=(sum(dXP.*dXP,1)-0.5*sum(VdXP.*VdXP,1))';
      nlp=nlp+work.L;
    end
    nlx=1;
    for nx=1:Nx,
      dXP=X(:,nx(work.onesNp))-P;
      VdXP=work.Vx(:,nlx:nlx+work.L-1)'*dXP;
      dist(nx,:)=dist(nx,:)-0.5*sum(VdXP.*VdXP,1);
      nlx=nlx+work.L;
    end
  end

  md=dist<eps;
  if sum(md(:))>0,
    dist(md)=0.1*min(dist(~md));
  end
  dist=1./dist;

  S=sum(dist,2);
  mXX=(reshape(sum(repmat(dist,DD,1).*PP(ind2,:),2),Nx,DD)./S(:,onesDD))';
  dXX=mXX-XX;

  %%% Compute statistics %%%
  if work.MAD;
    E=sum(sum(abs(dXX),2).*work.xxsd)/(Nx*DD);
  else
    E=sqrt(sum(sum(dXX.*dXX,2).*work.xxsd)/(Nx*DD));
  end
  if nargout>1,
    tanhXX=tanh(work.slope*sum(dXX.*dXX,1))';
    J=sum(tanhXX)/Nx;
    if ~isfinite(J),
      E=1;
    end
  end

  %%% Compute gradient %%%
  if nargout>2,
    dist=dist.*dist;
    fact=repmat((1-tanhXX.*tanhXX)./S,Np,1).*dist(:);
    if work.indepPP,
      fPP=permute(sum(reshape(fact(:,onesDD).*repmat(dXX,1,Np)',Nx,Np,DD)),[3 2 1]);
    else
      fPP=sum(reshape(fact.*sum(repmat(dXX,1,Np),1)',Nx,Np),1);
    end
    fact=fact.*sum(repmat(dXX,1,Np).*(repmat(mXX,1,Np)-PP(:,ind1)),1)';

    if work.dtype.euclidean,
      fact=reshape(fact(:,onesDr)'.*(repmat(X,1,Np)-P(:,ind1)),[Dr Nx Np]);
      fP=-permute(sum(fact,2),[1 3 2]);
      fX=sum(fact,3);
    elseif work.dtype.cosine,
      %fP=-permute(sum(reshape(fact(:,onesDr)'.*repmat(X,1,Np),[Dr Nx Np]),2),[1 3 2]);
      %fX=-sum(reshape(fact(:,onesDr)'.*P(:,ind1),[Dr Nx Np]),3);
    elseif work.dtype.rtangent,
    elseif work.dtype.otangent,
    elseif work.dtype.atangent,
    end
  end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [E, J, fX, fP, fPP] = ldppr_sindex(P, PP, X, XX, work)

  Dr=work.Dr;
  DD=work.DD;
  Np=work.Np;
  Nx=work.Nx;
  onesDr=work.onesDr;
  onesDD=work.onesDD;
  ind1=work.ind1;
  ind2=work.ind2;

  %%% Compute distances %%%
  if work.dtype.euclidean,
    x2=sum((X.^2),1)';
    p2=sum((P.^2),1);
    dist=X'*P;
    dist=x2(:,work.onesNp)+p2(work.onesNx,:)-dist-dist;
  elseif work.dtype.cosine,
    psd=sqrt(sum(P.*P,1));
    P=P./psd(onesDr,:);
    xsd=sqrt(sum(X.*X,1));
    X=X./xsd(onesDr,:);
    dist=1-X'*P;
  end

  md=dist<eps;
  if sum(md(:))>0,
    dist(md)=0.1*min(dist(~md));
  end
  dist=1./dist;

  S=sum(dist,2);
  mXX=(reshape(sum(repmat(dist,DD,1).*PP(ind2,:),2),Nx,DD)./S(:,onesDD))';
  dXX=mXX-XX;
  tanhXX=tanh(work.slope*sum(dXX.*dXX,1))';

  %%% Compute statistics %%%
  if work.MAD;
    E=sum(sum(abs(dXX),2).*work.xxsd)/(Nx*DD);
  else
    E=sqrt(sum(sum(dXX.*dXX,2).*work.xxsd)/(Nx*DD));
  end
  J=sum(tanhXX)/Nx;

  %%% Compute gradient %%%
  dist=dist.*dist;
  fact=repmat((1-tanhXX.*tanhXX)./S,Np,1).*dist(:);
  if work.indepPP,
    fPP=permute(sum(reshape(fact(:,onesDD).*repmat(dXX,1,Np)',Nx,Np,DD)),[3 2 1]);
  else
    fPP=sum(reshape(fact.*sum(repmat(dXX,1,Np),1)',Nx,Np),1);
  end
  fact=fact.*sum(repmat(dXX,1,Np).*(repmat(mXX,1,Np)-PP(:,ind1)),1)';

  if work.dtype.euclidean,
    fact=reshape(fact(:,onesDr)'.*(repmat(X,1,Np)-P(:,ind1)),[Dr Nx Np]);
    fP=-permute(sum(fact,2),[1 3 2]);
    fX=sum(fact,3);
  elseif work.dtype.cosine,
    fP=-permute(sum(reshape(fact(:,onesDr)'.*repmat(X,1,Np),[Dr Nx Np]),2),[1 3 2]);
    fX=-sum(reshape(fact(:,onesDr)'.*P(:,ind1),[Dr Nx Np]),3);
  end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [mu, ind] = kmeans(X, K)
  maxI=100;
  N=size(X,2);

  if K==1,
    mu=mean(X,2);
    if nargout>1,
      ind=ones(N,1);
    end
    return;
  elseif K==N,
    mu=X;
    if nargout>1,
      ind=[1:N]';
    end
    return;
  end

  onesN=ones(N,1);
  onesK=ones(K,1);
  [k,pind]=sort(rand(N,1));
  mu=X(:,pind(1:K));

  I=0;
  while true,
    x2=sum((X.^2),1)';
    mu2=sum((mu.^2),1);
    dist=X'*mu;
    dist=x2(:,onesK)+mu2(onesN,:)-dist-dist;
    [dist,ind]=min(dist,[],2);

    if I==maxI || sum(ind~=pind)==0,
      break;
    end

    kk=unique(ind);
    if size(kk,1)~=K,
      for k=1:K,
        if sum(kk==k)==0,
          mu(:,k)=X(:,round((N-1)*rand)+1);
        end
      end
    end

    for k=kk',
      mu(:,k)=mean(X(:,ind==k),2);
    end

    pind=ind;
    I=I+1;
  end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [ind1, ind2] = comp_ind(DD, Np, Nx, onesNx)
  if max(size(onesNx))==0,
    onesNx=ones(Nx,1);
  end

  ind1=1:Np;
  ind1=ind1(onesNx,:);
  ind1=ind1(:);

  ind2=1:DD;
  ind2=ind2(onesNx,:);
  ind2=ind2(:);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function X = orthonorm(X)
  [X,dummy]=qr(X,0);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function X = orthounit(X)
  [onX,dummy]=qr(X,0);
  X=onX.*repmat(sum(onX'*X,1),size(X,1),1);
  X=sqrt(size(X,2)).*X./sqrt(sum(diag(X'*X)));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function X = orthotangs(X,N)
  for n=N:N:size(X,2),
    [XX,dummy]=qr(X(:,n-N+1:n),0);
    X(:,n-N+1:n)=XX;
  end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function cfg = comptangs(B,P,cfg)
  %%% X tangents %%%
  if cfg.dtype.otangent || cfg.dtype.atangent,
    if cfg.knntangs && cfg.imgtangs,
      %cfg.Vx(:,cfg.knntangsx)=tangVects(cfg.rX,cfg.knntypes,'Xlabels',cfg.Xlabels);
      cfg.Vx(:,cfg.knntangsx)=tangVects(cfg.rX,cfg.knntypes);
      cfg.Vx(:,~cfg.knntangsx)=B'*cfg.oVx;
      if cfg.devel,
        %cfg.Vy(:,cfg.knntangsy)=tangVects(cfg.rY,cfg.knntypes,'Xlabels',cfg.Ylabels);
        cfg.Vy(:,cfg.knntangsy)=tangVects(cfg.rY,cfg.knntypes);
        cfg.Vy(:,~cfg.knntangsy)=B'*cfg.oVy;
      end
    elseif cfg.knntangs,
      %cfg.Vx=tangVects(cfg.rX,cfg.knntypes,'Xlabels',cfg.Xlabels);
      cfg.Vx=tangVects(cfg.rX,cfg.knntypes);
      if cfg.devel,
        %cfg.Vy=tangVects(cfg.rY,cfg.knntypes,'Xlabels',cfg.Ylabels);
        cfg.Vy=tangVects(cfg.rY,cfg.knntypes);
      end
    elseif cfg.imgtangs,
      cfg.Vx=B'*cfg.oVx;
      if cfg.devel,
        cfg.Vy=B'*cfg.oVy;
      end
    end
    cfg.Vx=orthotangs(cfg.Vx,cfg.L);
    if cfg.devel,
      cfg.Vy=orthotangs(cfg.Vy,cfg.L);
    end
  end
  %%% P tangents %%%
  if cfg.dtype.rtangent || cfg.dtype.atangent,
    if cfg.imgtangs,
      if cfg.normalize || cfg.linearnorm,
        P=P.*cfg.xsd(cfg.xsd~=0,cfg.onesNp)+cfg.xmu(cfg.xsd~=0,cfg.onesNp);
        if sum(cfg.xsd==0)>0,
          oP=P;
          P=cfg.xmu(:,cfg.onesNp);
          P(cfg.xsd~=0,:)=oP;
        end
      end
      imgVp=tangVects(P,cfg.imgtypes,cfg.imgtangcfg);
      onesNivp=ones(size(imgVp,2),1);
      if cfg.normalize || cfg.linearnorm,
        imgVp=(imgVp-cfg.xmu(:,onesNivp))./cfg.xsd(:,onesNivp);
        if sum(cfg.xsd==0)>0,
          imgVp(cfg.xsd==0,:)=[];
        end
      end
    end
    if cfg.knntangs && cfg.imgtangs,
      %cfg.Vp(:,cfg.knntangsp)=tangVects(cfg.rP,cfg.knntypes,'Xlabels',cfg.Plabels,'knnprotos',cfg.rX,cfg.Xlabels);
      cfg.Vp(:,cfg.knntangsp)=tangVects(cfg.rP,cfg.knntypes,'knnprotos',cfg.rX,[]);
      cfg.Vp(:,~cfg.knntangsp)=B'*imgVp;
    elseif cfg.knntangs,
      %cfg.Vp=tangVects(cfg.rP,cfg.knntypes,'Xlabels',cfg.Plabels,'knnprotos',cfg.rX,cfg.Xlabels);
      cfg.Vp=tangVects(cfg.rP,cfg.knntypes,'knnprotos',cfg.rX,[]);
    elseif cfg.imgtangs,
      cfg.Vp=B'*imgVp;
    end
    cfg.Vp=orthotangs(cfg.Vp,cfg.L);
  end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [P0, PP0] = ldppr_initP(X, XX, M, varargin)
%
% LDPPR_INITP: Initialize Prototypes for LDPPR
%
% [P0, PP0] = ldppr_initP(X, XX, M)
%
%   Input:
%     X       - Independent data matrix. Each column vector is a data point.
%     XX      - Dependent data matrix.
%     M       - Number of prototypes.
%
%   Input (optional):
%     'extra',EXTRA              - Extrapolate EXTRA from extreme values (defaul=false)
%     'multi',MULT               - Multimodal prototypes, MULT-means (defaul=false)
%     'seed',SEED                - Random seed (default=system)
%
%   Output:
%     P0      - Initialized prototypes. Independent data.
%     PP0     - Initialized prototypes. Dependent data.
%

fn='ldppr_initP:';
minargs=3;

P0=[];
PP0=[];

seed=rand('state');

logfile=2;

n=1;
argerr=false;
while size(varargin,2)>0,
  if ~ischar(varargin{n}) || size(varargin,2)<n+1,
    argerr=true;
  elseif strcmp(varargin{n},'extra') || ...
         strcmp(varargin{n},'seed') || ...
         strcmp(varargin{n},'multi'),
    eval([varargin{n},'=varargin{n+1};']);
    if ~isnumeric(varargin{n+1}) || sum(varargin{n+1}<0),
      argerr=true;
    else
      n=n+2;
    end
  else
    argerr=true;
  end
  if argerr || n>size(varargin,2),
    break;
  end
end

if argerr,
  fprintf(logfile,'%s error: incorrect input argument %d (%s,%g)\n',fn,n+minargs,varargin{n},varargin{n+1});
  return;
elseif nargin-size(varargin,2)~=minargs,
  fprintf(logfile,'%s error: not enough input arguments\n',fn);
  return;
elseif exist('multi','var') && mod(M,multi)~=0,
  fprintf(logfile,'%s error: the number of prototypes should be a multiple of MULT\n',fn);
  return;
end

DD=size(XX,1);

mx=max(XX');
mn=min(XX');

if exist('extra','var'),
  omx=mx;
  omn=mn;
  mx=omx+extra.*(omx-omn);
  mn=omn-extra.*(omx-omn);
end

if ~exist('multi','var'),
  multi=1;
else
  M=M/multi;
end

rand('state',seed);

if DD==1,

  d=(mx-mn)/(M-1);

  for m=mn:d:mx,
    s=XX>=m-d/2 & XX<m+d/2;
    if sum(s)>multi,
      P0=[P0,kmeans(X(:,s),multi)];
      seed=rand('state');
    else
      [mdist,idx]=sort(abs(XX-m));
      P0=[P0,X(:,idx(1:multi))];
    end
    PP0=[PP0,m*ones(1,multi)];
  end

elseif DD==2,

  M=round(sqrt(M));
  d=(mx-mn)/(M-1);

  Nx=size(XX,2);
  onesNx=ones(Nx,1);

  for m=mn(1):d(1):mx(1),
    sm=XX(1,:)>=m-d(1)/2 & XX(1,:)<m+d(1)/2;
    for n=mn(2):d(2):mx(2),
      sn=XX(2,:)>=n-d(2)/2 & XX(2,:)<n+d(2)/2;
      s=sm&sn;
      if sum(s)>multi,
        P0=[P0,kmeans(X(:,s),multi)];
        seed=rand('state');
      else
        mu=[m;n];
        mdist=sum((XX-mu(:,onesNx)).^2,1);
        [mdist,idx]=sort(mdist);
        P0=[P0,X(:,idx(1:multi))];
      end
      PP0=[PP0,[m;n]*ones(1,multi)];
    end
  end
  
else
  fprintf(logfile,'%s error: dimensionality of dependent data higher than two not supported\n',fn);
end
