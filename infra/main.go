package main

import (
	"github.com/pulumi/pulumi-docker-build/sdk/go/dockerbuild"
	"github.com/pulumi/pulumi-gcp/sdk/v10/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v10/go/gcp/cloudrunv2"
	"github.com/pulumi/pulumi-gcp/sdk/v10/go/gcp/organizations"
	"github.com/pulumi/pulumi-gcp/sdk/v10/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v10/go/gcp/secretmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v10/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// stack is the whole stack config. See README.md for how to set it.
type stack struct {
	Project     string
	Region      string
	NeonAuthURL string
	DatabaseURL pulumi.StringOutput
}

func loadStack(ctx *pulumi.Context) stack {
	gcp := config.New(ctx, "gcp")
	aloft := config.New(ctx, "aloft")
	region := gcp.Get("region")
	if region == "" {
		region = "us-east4"
	}
	return stack{
		Project:     gcp.Require("project"),
		Region:      region,
		NeonAuthURL: aloft.Require("neonAuthUrl"),
		DatabaseURL: aloft.RequireSecret("databaseUrl"),
	}
}

func main() { pulumi.Run(deploy) }

func deploy(ctx *pulumi.Context) error {
	s := loadStack(ctx)

	// iam is here because creating the service account below calls the IAM API.
	var apis []pulumi.Resource
	for _, api := range []string{"run", "artifactregistry", "secretmanager", "iam"} {
		svc, err := projects.NewService(ctx, api, &projects.ServiceArgs{
			Project:          pulumi.String(s.Project),
			Service:          pulumi.String(api + ".googleapis.com"),
			DisableOnDestroy: pulumi.Bool(false),
		})
		if err != nil {
			return err
		}
		apis = append(apis, svc)
	}
	afterAPIs := pulumi.DependsOn(apis)

	repo, err := artifactregistry.NewRepository(ctx, "aloft", &artifactregistry.RepositoryArgs{
		Project:      pulumi.String(s.Project),
		Location:     pulumi.String(s.Region),
		RepositoryId: pulumi.String("aloft"),
		Format:       pulumi.String("DOCKER"),
	}, afterAPIs)
	if err != nil {
		return err
	}

	client, err := organizations.GetClientConfig(ctx)
	if err != nil {
		return err
	}
	registry := s.Region + "-docker.pkg.dev"
	image, err := dockerbuild.NewImage(ctx, "api", &dockerbuild.ImageArgs{
		Context:   &dockerbuild.BuildContextArgs{Location: pulumi.String("../backend")},
		Platforms: dockerbuild.PlatformArray{dockerbuild.Platform_Linux_amd64},
		Push:      pulumi.Bool(true),
		Tags: pulumi.StringArray{
			pulumi.Sprintf("%s/%s/%s/api:latest", registry, s.Project, repo.RepositoryId),
		},
		Registries: dockerbuild.RegistryArray{&dockerbuild.RegistryArgs{
			Address:  pulumi.String(registry),
			Username: pulumi.String("oauth2accesstoken"),
			Password: pulumi.ToSecret(pulumi.String(client.AccessToken)).(pulumi.StringOutput),
		}},
	})
	if err != nil {
		return err
	}

	secret, err := secretmanager.NewSecret(ctx, "database-url", &secretmanager.SecretArgs{
		Project:     pulumi.String(s.Project),
		SecretId:    pulumi.String("database-url"),
		Replication: &secretmanager.SecretReplicationArgs{Auto: &secretmanager.SecretReplicationAutoArgs{}},
	}, afterAPIs)
	if err != nil {
		return err
	}
	version, err := secretmanager.NewSecretVersion(ctx, "database-url", &secretmanager.SecretVersionArgs{
		Secret:     secret.ID(),
		SecretData: s.DatabaseURL,
	})
	if err != nil {
		return err
	}

	account, err := serviceaccount.NewAccount(ctx, "aloft-api", &serviceaccount.AccountArgs{
		Project:     pulumi.String(s.Project),
		AccountId:   pulumi.String("aloft-api"),
		DisplayName: pulumi.String("Aloft API"),
	}, afterAPIs)
	if err != nil {
		return err
	}
	access, err := secretmanager.NewSecretIamMember(ctx, "aloft-api-database-url", &secretmanager.SecretIamMemberArgs{
		Project:  pulumi.String(s.Project),
		SecretId: secret.SecretId,
		Role:     pulumi.String("roles/secretmanager.secretAccessor"),
		Member:   account.Member,
	})
	if err != nil {
		return err
	}

	service, err := cloudrunv2.NewService(ctx, "aloft-api", &cloudrunv2.ServiceArgs{
		Project:            pulumi.String(s.Project),
		Location:           pulumi.String(s.Region),
		Name:               pulumi.String("aloft-api"),
		Ingress:            pulumi.String("INGRESS_TRAFFIC_ALL"),
		DeletionProtection: pulumi.Bool(false),
		Template: &cloudrunv2.ServiceTemplateArgs{
			ServiceAccount: account.Email,
			// Migrations run at start, so a second instance would race the first.
			Scaling: &cloudrunv2.ServiceTemplateScalingArgs{
				MinInstanceCount: pulumi.Int(0),
				MaxInstanceCount: pulumi.Int(1),
			},
			Containers: cloudrunv2.ServiceTemplateContainerArray{&cloudrunv2.ServiceTemplateContainerArgs{
				Image: image.Ref,
				Ports: &cloudrunv2.ServiceTemplateContainerPortsArgs{ContainerPort: pulumi.Int(9090)},
				Envs: cloudrunv2.ServiceTemplateContainerEnvArray{
					&cloudrunv2.ServiceTemplateContainerEnvArgs{Name: pulumi.String("ADDRESS"), Value: pulumi.String(":9090")},
					&cloudrunv2.ServiceTemplateContainerEnvArgs{Name: pulumi.String("NEON_AUTH_URL"), Value: pulumi.String(s.NeonAuthURL)},
					&cloudrunv2.ServiceTemplateContainerEnvArgs{
						Name: pulumi.String("DATABASE_URL"),
						ValueSource: &cloudrunv2.ServiceTemplateContainerEnvValueSourceArgs{
							SecretKeyRef: &cloudrunv2.ServiceTemplateContainerEnvValueSourceSecretKeyRefArgs{
								Secret:  secret.SecretId,
								Version: pulumi.String("latest"),
							},
						},
					},
				},
				StartupProbe: &cloudrunv2.ServiceTemplateContainerStartupProbeArgs{
					HttpGet: &cloudrunv2.ServiceTemplateContainerStartupProbeHttpGetArgs{Path: pulumi.String("/healthz")},
				},
			}},
		},
	}, pulumi.DependsOn(append(apis, version, access)))
	if err != nil {
		return err
	}

	// Every RPC still needs a Neon Auth JWT; public invoke only lets the request reach the API.
	if _, err := cloudrunv2.NewServiceIamMember(ctx, "aloft-api-public", &cloudrunv2.ServiceIamMemberArgs{
		Project:  pulumi.String(s.Project),
		Location: pulumi.String(s.Region),
		Name:     service.Name,
		Role:     pulumi.String("roles/run.invoker"),
		Member:   pulumi.String("allUsers"),
	}); err != nil {
		return err
	}

	ctx.Export("url", service.Uri)
	ctx.Export("image", image.Ref)
	return nil
}
